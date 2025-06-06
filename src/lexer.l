/*
 * avrdude - A Downloader/Uploader for AVR device programmers
 * Copyright (C) 2000-2004  Brian S. Dean <bsd@bdmicro.com>
 * Copyright (C) 2006 Joerg Wunsch <j@uriah.heep.sax.de>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/* $Id$ */

%{
#include <math.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "ac_cfg.h"
#include "avrdude.h"
#include "libavrdude.h"
#include "config.h"

#include "config_gram.h"

#ifndef YYERRCODE
#define YYERRCODE 256
#endif

/* capture lvalue keywords to associate comments with that assignment */
#define ccap() capture_lvalue_kw(yytext, cfg_lineno)

static void adjust_cfg_lineno(const char *p) {
  while(*p)
    if(*p++ == '\n')
      cfg_lineno++;
}

%}

  // AVRDUDE integer size suffix (LL/L/S/H/HH)
SIZS ([lL][lL]|[lL]|[sS]|[hH]|[hH][hH])
 // AVRDUDE integer suffix incl unsigned designator
ISUF ([uU]|[uU]{SIZS}|{SIZS}[uU]|{SIZS})
 // Non-negative integers
INUM (0|[1-9][0-9]*){ISUF}?
 // Octal integers
ONUM 0[0-7]+{ISUF}?
 // Binary integers
BNUM 0[bB][01]+{ISUF}?
 // Hexadecimal integers - fractional hexadecimals are treated below
XNUM 0[xX][0-9A-Fa-f]+{ISUF}?
RNUM (M{0,3})(D?C{0,3}|CM|CD)(L?X{0,3}|XC|XL)(V?I{0,3}|IX|IV)

 // Real numbers (decimal and hexadecimal fractional numbers)
SIGN [+-]
DNUM (([0-9]+[eE][-+]?[0-9]+)|([0-9]*\.[0-9]+([eE][-+]?[0-9]+)?))
HNUM (0[xX](([0-9A-Fa-f]+([pP][-+]?[0-9]+))|([0-9A-Fa-f]*\.[0-9A-Fa-f]+([pP][-+]?[0-9]+)?)))
NAN  [Nn][Aa][Nn]
INF  [Ii][Nn][Ff]([Ii][Nn][Ii][Tt][Yy])?


%option nounput

/* Bump resources for classic lex. */
%e2000
%p10000
%n1000

%%

({INUM}|{BNUM}|{ONUM}|{XNUM}|{RNUM}) { /* sign is treated in grammar */
  yylval = new_number(yytext);
  if(!yylval)
    return YYERRCODE;

  return TKN_NUMBER;
}

{SIGN}?({DNUM}|{HNUM}|{NAN}|{INF}) {
  yylval = new_number_real(yytext);
  if(!yylval)
    return YYERRCODE;

  return TKN_NUMBER_REAL;
}

["]([^"\\\n]|\\.|\\\n)*["] {
  char *str= mmt_strdup(yytext);
  cfg_unescape(str, str+1);
  size_t len = strlen(str);
  if(len)
    str[len-1] = 0;
  yylval = new_string(str);
  mmt_free(str);
  return TKN_STRING;
}

#\n#\ PROGRAMMER\ DEFINITIONS\n#\n+ { /* Record comments so far as prologue and skip */
  cfg_capture_prologue();
  adjust_cfg_lineno(yytext);
}

#\n#\ PART\ DEFINITIONS\n#\n+ { /* Ignore part definions header */
  adjust_cfg_lineno(yytext);
}

[ \t]*#[^\n]*\n+ { /* Record and skip # comments including preceding white space */
  capture_comment_str(yytext, cfg_lineno);
  adjust_cfg_lineno(yytext);
}

"/*" {  /* The following eats multiline C style comments, they are not captured */
        int c;
        int comment_start;
        
        comment_start = cfg_lineno;
        while (1) {
          while (((c = input()) != '*') && (c != EOF)) {
            /* eat up text of comment, but keep counting lines */
            if (c == '\n')
              cfg_lineno++;
          }
          
          if (c == '*') {
            while ((c = input()) == '*')
              ;
            if (c == '/')
              break;    /* found the end */
          }
          
          if (c == EOF) {
            yyerror("EOF in comment (started on line %d)", comment_start);
            return YYERRCODE;
          }
        }
     }


(?x: desc | prog_modes | is_serialadapter | extra_features | baudrate | usbvid | usbdev | usbsn | usbvendor | usbproduct |
  family_id | mcuid | n_interrupts | n_page_erase | n_boot_sections | boot_section_size |
  hvupdi_variant | stk500_devcode | avr910_devcode | chip_erase_delay | pagel | bs2 |
  timeout | stabdelay | cmdexedelay | synchloops | bytedelay | pollindex | pollvalue | predelay | postdelay | pollmethod |
  hventerstabdelay | progmodedelay | latchcycles | togglevtg | poweroffdelay | resetdelayms | resetdelayus | resetdelay | hvleavestabdelay |
  chiperasetime | (chiperase|program(fuse|lock))(polltimeout|pulsewidth) | synchcycles | hvspcmdexedelay |
  mcu_base | nvm_base | ocd_base | syscfg_base | ocdrev |
  autobaud_sync | factory_fcpu | idr | rampz | spmcr | eecr | eind |
  paged | size | num_pages | initval | bitmask | n_word_writes | offset | min_write_delay | max_write_delay | pwroff_after_write |
  readback_p1 | readback_p2 | mode | delay | blocksize | readsize ) {
  /* struct components for PROGRAMMER, AVRPART and AVRMEM */
  Component *cp = cfg_comp_search(yytext, current_strct);
  if(!cp) {
    yyerror("unknown component %s in %s", yytext, cfg_strct_name(current_strct));
    return YYERRCODE;
  }
  yylval = new_token(TKN_COMPONENT);
  yylval->value.comp = cp;
  ccap();
  return TKN_COMPONENT;
}


(?x: PM_(SPM|TPI|ISP|PDI|UPDI|HVSP|HVPP|debugWIRE|JTAG|JTAGmkI|XMEGAJTAG|AVR32JTAG|aWire) |
 HAS_(SUFFER|VTARG_SWITCH|VTARG_ADJ|VTARG_READ|FOSC_ADJ|VAREF_ADJ) |
 yes|no|pseudo | true|false ) { /* Constants */
  yylval = new_constant(yytext);
  return TKN_NUMBER;
}

alias            { yylval=NULL; return K_ALIAS; }
allow_subshells  { yylval=NULL; return K_ALLOW_SUBSHELLS; }
allowfullpagebitstream { yylval=NULL; ccap(); return K_ALLOWFULLPAGEBITSTREAM; }
avrdude_conf_version { yylval=NULL; return K_AVRDUDE_CONF_VERSION; }
buff             { yylval=NULL; ccap(); return K_BUFF; }
chip_erase       { yylval=new_token(K_CHIP_ERASE); ccap(); return K_CHIP_ERASE; }
connection_type  { yylval=NULL; ccap(); return K_CONNTYPE; }
dedicated        { yylval=new_token(K_DEDICATED); return K_DEDICATED; }
default_baudrate { yylval=NULL; return K_DEFAULT_BAUDRATE; }
default_bitclock { yylval=NULL; return K_DEFAULT_BITCLOCK; }
default_parallel { yylval=NULL; return K_DEFAULT_PARALLEL; }
default_programmer { yylval=NULL; return K_DEFAULT_PROGRAMMER; }
default_serial   { yylval=NULL; return K_DEFAULT_SERIAL; }
default_spi      { yylval=NULL; return K_DEFAULT_SPI; }
default_linuxgpio { yylval=NULL; return K_DEFAULT_LINUXGPIO; }
devicecode       { yylval=NULL; ccap(); return K_DEVICECODE; }
eeprom           { yylval=NULL; return K_EEPROM; }
eeprom_instr     { yylval=NULL; ccap(); return K_EEPROM_INSTR; }
enablepageprogramming { yylval=NULL; ccap(); return K_ENABLEPAGEPROGRAMMING; }
errled           { yylval=NULL; ccap(); return K_ERRLED; }
flash            { yylval=NULL; return K_FLASH; }
flash_instr      { yylval=NULL; ccap(); return K_FLASH_INSTR; }
has_debugwire    { yylval=NULL; ccap(); return K_HAS_DW; }
has_jtag         { yylval=NULL; ccap(); return K_HAS_JTAG; }
has_pdi          { yylval=NULL; ccap(); return K_HAS_PDI; }
has_tpi          { yylval=NULL; ccap(); return K_HAS_TPI; }
has_updi         { yylval=NULL; ccap(); return K_HAS_UPDI; }
hvsp_controlstack  { yylval=NULL; ccap(); return K_HVSP_CONTROLSTACK; }
hvupdi_support   { yylval=NULL; ccap(); return K_HVUPDI_SUPPORT; }
id               { yylval=NULL; ccap(); return K_ID; }
io               { yylval=new_token(K_IO); return K_IO; }
is_at90s1200     { yylval=NULL; ccap(); return K_IS_AT90S1200; }
is_avr32         { yylval=NULL; ccap(); return K_IS_AVR32; }
linuxgpio        { yylval=NULL; ccap(); return K_LINUXGPIO; }
load_ext_addr    { yylval=new_token(K_LOAD_EXT_ADDR); ccap(); return K_LOAD_EXT_ADDR; }
loadpage_hi      { yylval=new_token(K_LOADPAGE_HI); ccap(); return K_LOADPAGE_HI; }
loadpage_lo      { yylval=new_token(K_LOADPAGE_LO); ccap(); return K_LOADPAGE_LO; }
memory           { yylval=NULL; ccap(); current_strct = COMP_AVRMEM; return K_MEMORY; }
miso             { yylval=NULL; ccap(); yywarning("miso is deprecated, will be removed in v8.0, use sdi"); return K_SDI; }
mosi             { yylval=NULL; ccap(); yywarning("mosi is deprecated, will be removed in v8.0, use sdo"); return K_SDO; }
NULL             { yylval=NULL; return K_NULL; }
page_size        { yylval=NULL; ccap(); return K_PAGE_SIZE; }
parallel         { yylval=NULL; ccap(); return K_PARALLEL; }
parent           { yylval=NULL; return K_PARENT; }
part             { yylval=NULL; ccap(); current_strct = COMP_AVRPART; return K_PART; }
pgm_enable       { yylval=new_token(K_PGM_ENABLE); ccap(); return K_PGM_ENABLE; }
pgmled           { yylval=NULL; ccap(); return K_PGMLED; }
pp_controlstack  { yylval=NULL; ccap(); return K_PP_CONTROLSTACK; }
(programmer|serialadapter) { yylval=NULL; ccap(); current_strct = COMP_PROGRAMMER;
                   cx->lex_kw_is_programmer = *yytext == 'p'; return K_PROGRAMMER; }
rdyled           { yylval=NULL; ccap(); return K_RDYLED; }
read             { yylval=new_token(K_READ); ccap(); return K_READ; }
read_hi          { yylval=new_token(K_READ_HI); ccap(); return K_READ_HI; }
read_lo          { yylval=new_token(K_READ_LO); ccap(); return K_READ_LO; }
readback         { yylval=NULL; ccap(); return K_READBACK; }
reset            { yylval=new_token(K_RESET); ccap(); return K_RESET; }
retry_pulse      { yylval=NULL; ccap(); return K_RETRY_PULSE; }
sck              { yylval=new_token(K_SCK); ccap(); return K_SCK; }
sdi              { yylval=NULL; ccap(); return K_SDI; }
sdo              { yylval=NULL; ccap(); return K_SDO; }
serial           { yylval=NULL; ccap(); return K_SERIAL; }
signature        { yylval=NULL; ccap(); return K_SIGNATURE; }
spi              { yylval=NULL; return K_SPI; }
tck              { yylval=NULL; ccap(); return K_TCK; }
tdi              { yylval=NULL; ccap(); return K_TDI; }
tdo              { yylval=NULL; ccap(); return K_TDO; }
tms              { yylval=NULL; ccap(); return K_TMS; }
type             { yylval=NULL; ccap(); return K_TYPE; }
usb              { yylval=NULL; return K_USB; }
usbpid           { yylval=NULL; ccap(); return K_USBPID; }
variants         { yylval=NULL; ccap(); return K_VARIANTS; }
vcc              { yylval=NULL; ccap(); return K_VCC; }
vfyled           { yylval=NULL; ccap(); return K_VFYLED; }
write            { yylval=new_token(K_WRITE); ccap(); return K_WRITE; }
write_hi         { yylval=new_token(K_WRITE_HI); ccap(); return K_WRITE_HI; }
write_lo         { yylval=new_token(K_WRITE_LO); ccap(); return K_WRITE_LO; }
writepage        { yylval=new_token(K_WRITEPAGE); ccap(); return K_WRITEPAGE; }

","       { yylval = NULL; pyytext(); return TKN_COMMA; }
"="       { yylval = NULL; pyytext(); return TKN_EQUAL; }
";"       { yylval = NULL; pyytext(); return TKN_SEMI; }

"|"       { yylval = NULL; pyytext(); return OP_OR; }
"^"       { yylval = NULL; pyytext(); return OP_XOR; }
"&"       { yylval = NULL; pyytext(); return OP_AND; }
"+"       { yylval = NULL; pyytext(); return OP_PLUS; }
"-"       { yylval = NULL; pyytext(); return OP_MINUS; }
"*"       { yylval = NULL; pyytext(); return OP_TIMES; }
"/"       { yylval = NULL; pyytext(); return OP_DIVIDE; }
"%"       { yylval = NULL; pyytext(); return OP_MODULO; }
"~"       { yylval = NULL; pyytext(); return OP_TILDE; }

"("       { yylval = NULL; pyytext(); return TKN_LEFT_PAREN; }
")"       { yylval = NULL; pyytext(); return TKN_RIGHT_PAREN; }

"\n"      { cfg_lineno++; }
[ \r\t]+  { /* ignore whitespace */ }

c: { yyerror("possible old-style config file entry\n"
             "  Update your config file (see " CONFIG_DIR 
               "/avrdude.conf.sample for a sample)");
     return YYERRCODE; }

. { yyerror("unknown token");
     return YYERRCODE; }
%%

