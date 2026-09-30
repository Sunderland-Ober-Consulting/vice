/*
 * bustrace.c - Cycle-by-cycle bus trace of the C64, its drive and the IEC bus.
 *
 * Written by
 *  Kuba Sunderland-Ober
 *
 * This file is part of VICE, the Versatile Commodore Emulator.
 * See README for copyright notice.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
 *  02111-1307  USA.
 *
 */

/* The file format is described in doc/bus-trace.txt.

   Every stream is collected in a buffer of its own. A full buffer is written
   out as one chunk, so the chunks of different streams interleave in the
   file, while the records of one stream stay in that stream's order. Closing
   the trace writes the remaining buffers, the end chunk with the record count
   of every stream, and the final header.
*/

#include "vice.h"

#ifdef FEATURE_BUSTRACE

#include <stdio.h>
#include <string.h>

#include "bustrace.h"
#include "cmdline.h"
#include "drive.h"
#include "drivetypes.h"
#include "lib.h"
#include "log.h"
#include "machine.h"
#include "maincpu.h"
#include "resources.h"
#include "util.h"
#include "version.h"

#define BUSTRACE_VERSION     1
#define BUSTRACE_HEADER_SIZE 128
#define BUSTRACE_NUM_STREAMS 5
#define BUSTRACE_ALL_STREAMS 0x1f
#define BUSTRACE_BUFFER_SIZE (1024 * 1024)

#define C64_RECORD_SIZE   20
#define DRIVE_RECORD_SIZE 16
#define SYNC_RECORD_SIZE  16
#define IEC_RECORD_SIZE   16
#define TOD_RECORD_SIZE   24

/* The longest drive CPU loop iteration: an interrupt entry followed by the
   longest instruction, with room to spare. */
#define DRIVE_MAX_ACCESSES 32

unsigned int bustrace_active = 0;
int bustrace_c64_opcode_next = 0;

static char *trace_file_name = NULL;
static int trace_streams = BUSTRACE_ALL_STREAMS;
static int trace_start_clk = 0;
static int trace_stop_clk = 0;

static log_t bustrace_log = LOG_DEFAULT;

static FILE *trace_file = NULL;
static unsigned int file_streams = 0;
static CLOCK window_start = 0;   /* first main clock written */
static CLOCK window_stop = 0;    /* 0: unbounded */
static CLOCK first_c64_clk = 0;
static int have_c64_record = 0;
static int write_failed = 0;

typedef struct stream_buffer_s {
    uint8_t *data;
    size_t fill;
    size_t record_size;
    uint64_t records;
} stream_buffer_t;

static stream_buffer_t streams[BUSTRACE_NUM_STREAMS + 1];

static const size_t record_sizes[BUSTRACE_NUM_STREAMS + 1] = {
    0, C64_RECORD_SIZE, DRIVE_RECORD_SIZE, SYNC_RECORD_SIZE, IEC_RECORD_SIZE, TOD_RECORD_SIZE
};

/* ------------------------------------------------------------------------- */

static void put_le16(uint8_t *p, unsigned int v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put_le32(uint8_t *p, uint32_t v)
{
    put_le16(p, v & 0xffff);
    put_le16(p + 2, v >> 16);
}

static void put_le64(uint8_t *p, uint64_t v)
{
    put_le32(p, (uint32_t)v);
    put_le32(p + 4, (uint32_t)(v >> 32));
}

static int in_window(CLOCK clk)
{
    return clk >= window_start && (window_stop == 0 || clk < window_stop);
}

static void file_write(const void *data, size_t size)
{
    if (!write_failed && fwrite(data, 1, size, trace_file) != size) {
        log_error(bustrace_log, "Cannot write to '%s'.", trace_file_name);
        write_failed = 1;
    }
}

static void flush_stream(int id)
{
    stream_buffer_t *s = &streams[id];
    uint8_t chunk[8];

    if (s->fill == 0) {
        return;
    }
    put_le32(chunk, (uint32_t)id);
    put_le32(chunk + 4, (uint32_t)s->fill);
    file_write(chunk, sizeof chunk);
    file_write(s->data, s->fill);
    s->fill = 0;
}

/* Returns space for one record of the stream, zeroed. */
static uint8_t *new_record(int id)
{
    stream_buffer_t *s = &streams[id];
    uint8_t *p;

    if (s->fill + s->record_size > BUSTRACE_BUFFER_SIZE) {
        flush_stream(id);
    }
    p = s->data + s->fill;
    memset(p, 0, s->record_size);
    s->fill += s->record_size;
    s->records++;
    return p;
}

/* Machine timing for the header. It is taken while the machine runs, since
   the trace may be closed on exit after the drives are gone. */
static uint32_t header_cycles_per_sec = 0;
static uint32_t header_drive_hz = 0;
static uint32_t header_drive_sync_factor = 0;

static void write_header(void)
{
    uint8_t h[BUSTRACE_HEADER_SIZE];

    memset(h, 0, sizeof h);
    memcpy(h, "VBTR", 4);
    put_le16(h + 4, BUSTRACE_VERSION);
    put_le16(h + 6, BUSTRACE_HEADER_SIZE);
    put_le32(h + 8, file_streams);
    put_le32(h + 12, header_cycles_per_sec);
    put_le64(h + 16, have_c64_record ? first_c64_clk : window_start);
    put_le64(h + 24, window_stop);
    put_le32(h + 32, header_drive_hz);
    put_le32(h + 36, header_drive_sync_factor);
    strncpy((char *)h + 40, VERSION, 31);
    file_write(h, sizeof h);
}

static void bustrace_close(void)
{
    uint8_t end[8 + 4 + BUSTRACE_NUM_STREAMS * 12];
    size_t len = 4;
    uint32_t count = 0;
    int id;

    if (trace_file == NULL) {
        return;
    }
    bustrace_active = 0;

    for (id = 1; id <= BUSTRACE_NUM_STREAMS; id++) {
        if (file_streams & BUSTRACE_MASK(id)) {
            flush_stream(id);
            put_le32(end + 12 + count * 12, (uint32_t)id);
            put_le64(end + 12 + count * 12 + 4, streams[id].records);
            count++;
            len += 12;
        }
    }
    put_le32(end, 0);
    put_le32(end + 4, (uint32_t)len);
    put_le32(end + 8, count);
    file_write(end, 8 + len);

    if (fseek(trace_file, 0, SEEK_SET) == 0) {
        write_header();
    } else {
        write_failed = 1;
    }
    if (fclose(trace_file) != 0 || write_failed) {
        log_error(bustrace_log, "Bus trace '%s' is incomplete.", trace_file_name);
    }
    trace_file = NULL;

    for (id = 1; id <= BUSTRACE_NUM_STREAMS; id++) {
        lib_free(streams[id].data);
        streams[id].data = NULL;
    }
}

static int bustrace_open(void)
{
    int id;

    trace_file = fopen(trace_file_name, "wb");
    if (trace_file == NULL) {
        log_error(bustrace_log, "Cannot open '%s' for writing.", trace_file_name);
        return -1;
    }
    write_failed = 0;
    file_streams = (unsigned int)trace_streams & BUSTRACE_ALL_STREAMS;

    /* A record is complete only from the first cycle that starts after the
       trace has been opened. */
    window_start = maincpu_clk + 1;
    if ((CLOCK)trace_start_clk > window_start) {
        window_start = (CLOCK)trace_start_clk;
    }
    window_stop = (CLOCK)trace_stop_clk;
    have_c64_record = 0;
    header_cycles_per_sec = (uint32_t)machine_get_cycles_per_second();
    header_drive_hz = 0;
    header_drive_sync_factor = 0;

    for (id = 1; id <= BUSTRACE_NUM_STREAMS; id++) {
        streams[id].data = lib_malloc(BUSTRACE_BUFFER_SIZE);
        streams[id].fill = 0;
        streams[id].record_size = record_sizes[id];
        streams[id].records = 0;
    }

    /* the final header is written on close */
    write_header();
    bustrace_active = file_streams;
    return 0;
}

/* ------------------------------------------------------------------------- */
/* c64 stream */

/* The record of the cycle in progress. */
static uint8_t c64_record[C64_RECORD_SIZE];
static CLOCK c64_record_clk;
static int c64_record_open = 0;

void bustrace_c64_cpu(uint16_t addr, uint8_t data, uint8_t flags)
{
    if (bustrace_c64_opcode_next && (flags & BUSTRACE_CPU_READ)) {
        flags |= BUSTRACE_CPU_OPCODE;
        bustrace_c64_opcode_next = 0;
    }
    if (!c64_record_open) {
        return;
    }
    if (!(c64_record[3] & BUSTRACE_CPU_NO_ACCESS)) {
        c64_record[3] |= BUSTRACE_CPU_MULTIPLE;
        return;
    }
    put_le16(c64_record, addr);
    c64_record[2] = data;
    c64_record[3] = (uint8_t)((c64_record[3] & ~BUSTRACE_CPU_NO_ACCESS) | flags);
}

void bustrace_c64_phi2_sprite(uint16_t addr, uint8_t data)
{
    if (c64_record_open) {
        put_le16(c64_record + 12, addr);
        c64_record[14] = data;
        c64_record[7] |= BUSTRACE_VIC_PHI2_VALID;
    }
}

void bustrace_c64_next_cycle(CLOCK clk, uint16_t phi1_addr, uint8_t phi1_data, uint8_t phi1_kind)
{
    if (c64_record_open && in_window(c64_record_clk)) {
        if (!have_c64_record) {
            first_c64_clk = c64_record_clk;
            have_c64_record = 1;
            header_cycles_per_sec = (uint32_t)machine_get_cycles_per_second();
        }
        memcpy(new_record(BUSTRACE_STREAM_C64), c64_record, C64_RECORD_SIZE);
    }

    memset(c64_record, 0, sizeof c64_record);
    c64_record_clk = clk;
    c64_record_open = 1;
    c64_record[3] = BUSTRACE_CPU_NO_ACCESS;
    put_le16(c64_record + 4, phi1_addr);
    c64_record[6] = phi1_data;
    c64_record[7] = phi1_kind;
    c64_record[19] = (uint8_t)clk;
}

void bustrace_c64_c_access(uint16_t addr, uint8_t data, uint8_t colour)
{
    if (c64_record_open) {
        put_le16(c64_record + 8, addr);
        c64_record[10] = data;
        c64_record[11] = colour;
        c64_record[7] |= BUSTRACE_VIC_C_VALID;
    }
}

void bustrace_c64_cycle_state(unsigned int line, unsigned int cycle, int ba_low,
                              int irq_low, int nmi_low, uint8_t iec_cpu_port)
{
    if (!c64_record_open) {
        return;
    }
    if (ba_low) {
        c64_record[3] |= BUSTRACE_CPU_BA_LOW;
    }
    if (irq_low) {
        c64_record[3] |= BUSTRACE_CPU_IRQ_LOW;
    }
    if (nmi_low) {
        c64_record[3] |= BUSTRACE_CPU_NMI_LOW;
    }
    c64_record[15] = iec_cpu_port;
    put_le16(c64_record + 16, line);
    c64_record[18] = (uint8_t)cycle;
}

/* ------------------------------------------------------------------------- */
/* drive8 and drive8.sync streams

   The drive hooks run while any of the drive8, drive8.sync and iec streams
   is on, since the iec stream stamps a drive write with its drive cycle. */

typedef struct drive_access_s {
    uint16_t addr;
    uint8_t data;
    uint8_t flags;
    uint8_t drv_port;
    CLOCK clk;
} drive_access_t;

static drive_access_t drive_accesses[DRIVE_MAX_ACCESSES];
static int drive_count = 0;
static int drive_opcode = -1;
static int drive_pending = 0;
static int drive_overflow = 0;
static int drive_in_window = 0;
static int sync_started = 0;
static CLOCK drive_start_clk;

/* Writes the accesses of one iteration of the drive CPU loop, which ran from
   drive_start_clk to end_clk. The core performs one access per cycle, so an
   access is stamped with the iteration's start clock plus its ordinal, with
   the exceptions described in doc/bus-trace.txt. */
static void drive_commit(CLOCK end_clk)
{
    CLOCK cycles = end_clk - drive_start_clk;
    CLOCK stamp;
    int drop = -1;
    uint8_t extra = 0;
    int i, ordinal = 0;

    if (!drive_pending) {
        return;
    }
    drive_pending = 0;

    if (drive_overflow) {
        log_error(bustrace_log, "Drive loop iteration at clock %"PRIu64" has more than %d accesses.",
                  drive_start_clk, DRIVE_MAX_ACCESSES);
        drive_overflow = 0;
    }

    /* RTS reads its return address twice; the first read is dropped. */
    if ((CLOCK)drive_count == cycles + 1 && drive_opcode >= 0
        && drive_accesses[drive_opcode].data == 0x60 && drive_opcode + 6 < drive_count) {
        drop = drive_opcode + 5;
    } else if ((CLOCK)drive_count != cycles) {
        extra = BUSTRACE_DRV_SHORT;
    }

    if (!drive_in_window || !(bustrace_active & BUSTRACE_MASK(BUSTRACE_STREAM_DRIVE8))) {
        return;
    }

    for (i = 0; i < drive_count; i++) {
        const drive_access_t *a = &drive_accesses[i];
        uint8_t flags = a->flags | extra;
        uint8_t *r;
        CLOCK late;

        if (i == drop) {
            continue;
        }
        if (drive_opcode >= 0) {
            if (i < drive_opcode) {
                flags |= BUSTRACE_DRV_INTERRUPT;
            } else if (i == drive_opcode) {
                flags |= BUSTRACE_DRV_OPCODE;
            }
        }
        if (drop >= 0 && i == drop + 1) {
            flags |= BUSTRACE_DRV_RTS_DUP;
        }
        stamp = drive_start_clk + (CLOCK)ordinal++;
        late = a->clk > stamp ? a->clk - stamp : 0;

        r = new_record(BUSTRACE_STREAM_DRIVE8);
        put_le64(r, stamp);
        put_le16(r + 8, a->addr);
        r[10] = a->data;
        r[11] = flags;
        put_le16(r + 12, late > 0xffff ? 0xffff : (unsigned int)late);
        r[14] = a->drv_port;
    }
}

/* A catch-up runs the drive from drive_clk, where the previous one ended at
   main clock main_from, until main clock main_to. The first catch-up in the
   window also writes its starting point, so that every traced drive cycle
   lies between two sync records. */
void bustrace_drive_execute_begin(CLOCK main_from, CLOCK main_to, CLOCK drive_clk)
{
    uint8_t *r;

    drive_in_window = in_window(main_to);
    if (drive_in_window && header_drive_hz == 0) {
        diskunit_context_t *unit = diskunit_context[0];

        header_drive_hz = (uint32_t)(1000000 * unit->clock_frequency);
        header_drive_sync_factor = (uint32_t)unit->cpud->sync_factor;
    }
    if (drive_in_window && !sync_started
        && (bustrace_active & BUSTRACE_MASK(BUSTRACE_STREAM_DRIVE8_SYNC))) {
        r = new_record(BUSTRACE_STREAM_DRIVE8_SYNC);
        put_le64(r, main_from);
        put_le64(r + 8, drive_clk);
        sync_started = 1;
    }
}

void bustrace_drive_iteration(CLOCK drive_clk)
{
    drive_commit(drive_clk);
    drive_start_clk = drive_clk;
    drive_count = 0;
    drive_opcode = -1;
    drive_pending = 1;
}

void bustrace_drive_opcode(void)
{
    drive_opcode = drive_count;
}

void bustrace_drive_access(uint16_t addr, uint8_t data, uint8_t flags, CLOCK drive_clk, uint8_t drv_port)
{
    drive_access_t *a;

    if (!drive_pending) {
        return;
    }
    if (drive_count == DRIVE_MAX_ACCESSES) {
        drive_overflow = 1;
        return;
    }
    a = &drive_accesses[drive_count++];
    a->addr = addr;
    a->data = data;
    a->flags = flags;
    a->drv_port = drv_port;
    a->clk = drive_clk;
}

/* The stamp of the latest drive access, for events it caused. */
CLOCK bustrace_drive_stamp(void)
{
    return drive_start_clk + (CLOCK)(drive_count > 0 ? drive_count - 1 : 0);
}

void bustrace_drive_execute_end(CLOCK main_clk, CLOCK drive_clk)
{
    uint8_t *r;

    drive_commit(drive_clk);
    if (drive_in_window && (bustrace_active & BUSTRACE_MASK(BUSTRACE_STREAM_DRIVE8_SYNC))) {
        r = new_record(BUSTRACE_STREAM_DRIVE8_SYNC);
        put_le64(r, main_clk);
        put_le64(r + 8, drive_clk);
    }
}

/* ------------------------------------------------------------------------- */
/* iec stream */

static uint8_t iec_last[4];
static int iec_have_last = 0;

void bustrace_iec(CLOCK clk, uint8_t cpu_bus, uint8_t drv_bus, uint8_t cpu_port,
                  uint8_t drv_port, int source)
{
    uint8_t now[4];
    uint8_t *r;

    now[0] = cpu_bus;
    now[1] = drv_bus;
    now[2] = cpu_port;
    now[3] = drv_port;
    if (iec_have_last && memcmp(now, iec_last, sizeof now) == 0) {
        return;
    }
    memcpy(iec_last, now, sizeof now);
    iec_have_last = 1;

    if (source == BUSTRACE_IEC_SOURCE_DRIVE ? !drive_in_window : !in_window(clk)) {
        return;
    }
    r = new_record(BUSTRACE_STREAM_IEC);
    put_le64(r, clk);
    memcpy(r + 8, now, sizeof now);
    r[12] = (uint8_t)source;
}

/* ------------------------------------------------------------------------- */
/* tod stream */

void bustrace_tod(CLOCK clk, int cia, int kind, const uint8_t *tod, const uint8_t *alarm,
                  const uint8_t *latch, uint8_t flags, uint8_t tickcounter)
{
    uint8_t *r;

    if (!in_window(clk)) {
        return;
    }
    r = new_record(BUSTRACE_STREAM_TOD);
    put_le64(r, clk);
    r[8] = (uint8_t)cia;
    r[9] = (uint8_t)kind;
    memcpy(r + 10, tod, 4);
    memcpy(r + 14, alarm, 4);
    memcpy(r + 18, latch, 4);
    r[22] = flags;
    r[23] = tickcounter;
}

/* ------------------------------------------------------------------------- */
/* resources and command line options */

static int set_trace_file_name(const char *name, void *param)
{
    bustrace_close();
    util_string_set(&trace_file_name, name);
    c64_record_open = 0;
    drive_pending = 0;
    sync_started = 0;
    iec_have_last = 0;
    if (trace_file_name != NULL && *trace_file_name != '\0') {
        return bustrace_open();
    }
    return 0;
}

static int set_trace_streams(int value, void *param)
{
    if (value < 0 || value > BUSTRACE_ALL_STREAMS) {
        return -1;
    }
    trace_streams = value;
    return 0;
}

static int set_trace_start_clk(int value, void *param)
{
    if (value < 0) {
        return -1;
    }
    trace_start_clk = value;
    return 0;
}

static int set_trace_stop_clk(int value, void *param)
{
    if (value < 0) {
        return -1;
    }
    trace_stop_clk = value;
    return 0;
}

static const resource_string_t resources_string[] = {
    { "BusTraceFile", "", RES_EVENT_NO, NULL,
      &trace_file_name, set_trace_file_name, NULL },
    RESOURCE_STRING_LIST_END
};

static const resource_int_t resources_int[] = {
    { "BusTraceStreams", BUSTRACE_ALL_STREAMS, RES_EVENT_NO, NULL,
      &trace_streams, set_trace_streams, NULL },
    { "BusTraceStartClk", 0, RES_EVENT_NO, NULL,
      &trace_start_clk, set_trace_start_clk, NULL },
    { "BusTraceStopClk", 0, RES_EVENT_NO, NULL,
      &trace_stop_clk, set_trace_stop_clk, NULL },
    RESOURCE_INT_LIST_END
};

int bustrace_resources_init(void)
{
    bustrace_log = log_open("BusTrace");

    /* the window and the streams are registered first, so that a trace
       file given on the command line is opened with them */
    if (resources_register_int(resources_int) < 0) {
        return -1;
    }
    return resources_register_string(resources_string);
}

void bustrace_resources_shutdown(void)
{
    bustrace_close();
    lib_free(trace_file_name);
    trace_file_name = NULL;
}

static const cmdline_option_t cmdline_options[] =
{
    { "-bustracefile", SET_RESOURCE, CMDLINE_ATTRIB_NEED_ARGS,
      NULL, NULL, "BusTraceFile", NULL,
      "<Name>", "Write a bus trace to the given file" },
    { "-bustracestreams", SET_RESOURCE, CMDLINE_ATTRIB_NEED_ARGS,
      NULL, NULL, "BusTraceStreams", NULL,
      "<Mask>", "Streams to trace: 1: C64, 2: drive 8, 4: drive 8 sync, 8: IEC bus, 16: CIA TOD" },
    { "-bustracestart", SET_RESOURCE, CMDLINE_ATTRIB_NEED_ARGS,
      NULL, NULL, "BusTraceStartClk", NULL,
      "<Clock>", "First CPU clock to trace (0: from when the file is set)" },
    { "-bustracestop", SET_RESOURCE, CMDLINE_ATTRIB_NEED_ARGS,
      NULL, NULL, "BusTraceStopClk", NULL,
      "<Clock>", "CPU clock at which tracing stops (0: never)" },
    CMDLINE_LIST_END
};

int bustrace_cmdline_options_init(void)
{
    return cmdline_register_options(cmdline_options);
}

#endif /* FEATURE_BUSTRACE */
