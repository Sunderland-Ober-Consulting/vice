/*
 * bustrace.h - Cycle-by-cycle bus trace of the C64, its drive and the IEC bus.
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

/* The file format is described in doc/bus-trace.txt. */

#ifndef VICE_BUSTRACE_H
#define VICE_BUSTRACE_H

#include "types.h"

#define BUSTRACE_STREAM_C64         1
#define BUSTRACE_STREAM_DRIVE8      2
#define BUSTRACE_STREAM_DRIVE8_SYNC 3
#define BUSTRACE_STREAM_IEC         4
#define BUSTRACE_STREAM_TOD         5

#define BUSTRACE_MASK(stream) (1U << ((stream) - 1))

/* c64 stream, CPU flags */
#define BUSTRACE_CPU_READ      0x01
#define BUSTRACE_CPU_DUMMY     0x02
#define BUSTRACE_CPU_OPCODE    0x04
#define BUSTRACE_CPU_NO_ACCESS 0x08
#define BUSTRACE_CPU_BA_LOW    0x10
#define BUSTRACE_CPU_IRQ_LOW   0x20
#define BUSTRACE_CPU_NMI_LOW   0x40
#define BUSTRACE_CPU_MULTIPLE  0x80

/* c64 stream, VIC-II phi1 fetch kinds (bits 0-2 of the VIC flags) */
#define BUSTRACE_PHI1_IDLE        0
#define BUSTRACE_PHI1_G           1
#define BUSTRACE_PHI1_IDLE_G      2
#define BUSTRACE_PHI1_REFRESH     3
#define BUSTRACE_PHI1_SPRITE_PTR  4
#define BUSTRACE_PHI1_SPRITE_DMA  5

#define BUSTRACE_VIC_C_VALID      0x08
#define BUSTRACE_VIC_PHI2_VALID   0x10

/* drive8 stream flags */
#define BUSTRACE_DRV_READ         0x01
#define BUSTRACE_DRV_DUMMY        0x02
#define BUSTRACE_DRV_OPCODE       0x04
#define BUSTRACE_DRV_INTERRUPT    0x08
#define BUSTRACE_DRV_SHORT        0x10
#define BUSTRACE_DRV_RTS_DUP      0x20

/* iec stream sources */
#define BUSTRACE_IEC_SOURCE_CPU   0
#define BUSTRACE_IEC_SOURCE_DRIVE 1

/* tod stream kinds and flags */
#define BUSTRACE_TOD_TICK         0
#define BUSTRACE_TOD_READ         1
#define BUSTRACE_TOD_WRITE        2
#define BUSTRACE_TOD_ALARM_WRITE  3

#define BUSTRACE_TOD_STOPPED      0x01
#define BUSTRACE_TOD_LATCHED      0x02
#define BUSTRACE_TOD_MATCH        0x04
#define BUSTRACE_TOD_ICR          0x08
#define BUSTRACE_TOD_UPDATE       0x10

#ifdef FEATURE_BUSTRACE

/* The streams being written; zero while no trace file is open. */
extern unsigned int bustrace_active;

#define BUSTRACE_ON(stream) (bustrace_active & BUSTRACE_MASK(stream))

int bustrace_resources_init(void);
void bustrace_resources_shutdown(void);
int bustrace_cmdline_options_init(void);

/* c64: the CPU access of the current cycle */
extern int bustrace_c64_opcode_next;
void bustrace_c64_cpu(uint16_t addr, uint8_t data, uint8_t flags);

/* c64: the VIC-II, in the order vicii_cycle() performs its work */
void bustrace_c64_phi2_sprite(uint16_t addr, uint8_t data);
void bustrace_c64_next_cycle(CLOCK clk, uint16_t phi1_addr, uint8_t phi1_data, uint8_t phi1_kind);
void bustrace_c64_c_access(uint16_t addr, uint8_t data, uint8_t colour);
void bustrace_c64_cycle_state(unsigned int line, unsigned int cycle, int ba_low,
                              int irq_low, int nmi_low, uint8_t iec_cpu_port);

/* drive 8 */
void bustrace_drive_execute_begin(CLOCK main_from, CLOCK main_to, CLOCK drive_clk);
void bustrace_drive_iteration(CLOCK drive_clk);
void bustrace_drive_opcode(void);
void bustrace_drive_access(uint16_t addr, uint8_t data, uint8_t flags, CLOCK drive_clk, uint8_t drv_port);
CLOCK bustrace_drive_stamp(void);
void bustrace_drive_execute_end(CLOCK main_clk, CLOCK drive_clk);

/* IEC bus: written when any of the lines changes */
void bustrace_iec(CLOCK clk, uint8_t cpu_bus, uint8_t drv_bus, uint8_t cpu_port,
                  uint8_t drv_port, int source);

/* CIA time of day */
void bustrace_tod(CLOCK clk, int cia, int kind, const uint8_t *tod, const uint8_t *alarm,
                  const uint8_t *latch, uint8_t flags, uint8_t tickcounter);

#endif /* FEATURE_BUSTRACE */

#endif
