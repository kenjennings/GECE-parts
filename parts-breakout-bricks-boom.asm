;===============================================================================
; Breakout Arcade -- 1976
; Conceptualized by Nolan Bushnell and Steve Bristow.
; Built by Steve Wozniak.
; https://en.wikipedia.org/wiki/Breakout_(video_game)
;===============================================================================
; C64 Breakout clone -- 2016
; Written by Darren Du Vall aka Sausage-Toes
; source at: 
; Github: https://github.com/Sausage-Toes/C64_Breakout
;===============================================================================
; C64 Breakout clone ported to Atari 8-bit -- 2017
; Atari-fied by Ken Jennings
; Build for Atari using eclipse/wudsn/atasm on linux
; Source at:
; Github: https://github.com/kenjennings/C64-Breakout-for-Atari
; Google Drive: https://drive.google.com/drive/folders/0B2m-YU97EHFESGVkTXp3WUdKUGM
;===============================================================================
; Breakout: Gratuitous Eye Candy Edition -- 2017
; Written by Ken Jennings
; Build for Atari using eclipse/wudsn/atasm on linux
; Source at:
; Github: https://github.com/kenjennings/Atari-Breakout-GECE
; Google Drive: https://drive.google.com/drive/folders/
;===============================================================================

;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
;   ATARI SYSTEM INCLUDES
;===============================================================================
; Various Include files that provide equates defining 
; registers and the values used for the registers:
;
	.include "ANTIC.asm" 
	.include "GTIA.asm"
	.include "POKEY.asm"
	.include "PIA.asm"
	.include "OS.asm"
	.include "DOS.asm" ; This provides the LOMEM, start, and run addresses.

	.include "macros.asm"


	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

	.macro mDebugByte  ; Address, Y position
		.if %0<>2
			.error "DebugByte: incorrect number of arguments. 2 required!"
		.else
			lda %1
			ldy #%2
			jsr DiagByte
		.endif
	.endm


	
;===============================================================================
;   VARIOUS CONSTANTS AND LIMITS
;===============================================================================
; Let's define some useful offsets and sizes. 
; Could become useful somewhere else.
;
BRICK_LEFT_OFFSET =   3  ; offset from normal PLAYFIELD LEFT edge to left edge of brick 
BRICK_RIGHT_OFFSET =  12 ; offset from normal PLAYFIELD LEFT edge to the right edge of first brick

BRICK_PIXEL_WIDTH =   10 ; Actual drawn pixels in brick.
BRICK_WIDTH =         11 ; including the trailing blank space separating bricks 

BRICK_TOP_OFFSET =     78  ; First scan line of top line of bricks.
BRICK_TOP_END_OFFSET = 82  ; Last scan line of the top line of bricks.
BRICK_BOTTOM_OFFSET =  131 ; Last scan line of bottom line of bricks.

BRICK_LINE_HEIGHT =    5   ; Actual drawn graphics scanlines.
BRICK_HEIGHT =         7   ; including the following blank lines (used when multiplying for position) 
;
; Playfield MIN/MAX travel areas relative to the ball.
;
MIN_PIXEL_X = PLAYFIELD_LEFT_EDGE_NORMAL+BRICK_LEFT_OFFSET ; 48 + 3 = 51
MAX_PIXEL_X = MIN_PIXEL_X+152 ; Actual last color clock of last brick. 51 + 152 = 203

PIXELS_COLS = MAX_PIXEL_X-MIN_PIXEL_X+1 ; number of real pixels on line (153)

MIN_BALL_X =  MIN_PIXEL_X ; because PM/left edge is same
MAX_BALL_X =  MAX_PIXEL_X-1 ; because ball is 2 color clocks wide

MIN_PIXEL_Y = 55 ; Top edge of the playfield.  just a guess right now.
MAX_PIXEL_Y = 224 ; bottom edge after paddle.  lose ball here.

; Ball travel when bouncing from walls and bricks will simply negate 
; the current horizontal or vertical direction.
; Ball travel when bouncing off the paddle will require lookup tables
; to manage angle (and speed changes).
;
; Playfield MIN/MAX travel areas relative to the Paddle.
;
; Paddle travel is only horizontal. But the conversion from paddle 
; value (potentiometer) to paddle Player on screen will have different
; tables based on wide paddle and narrow paddle sizes.
; The paddle also is allowed to travel beyond the left and right sides
; of the playfield far enough that only an edge of the paddle is 
; visible for collision on the playfield.
; The size of the paddle varies the coordinates for this.
;
; Paddle limits:
; O = Offscreen/not playfield
; X = ignored playfield 
; P = Playfield 
; T = Paddle Pixels
;
; (Normal  Left)     (Normal Right)
; OOOxxxPP           PPxxxxOOO 
; TTTTTTTT           TTTTTTTT
; MIN = Playfield left edge normal - 3
; MAX = Playfield right edge - 5
;
; (Small  Left)     (Small Right)
; OOOxxxPP           PPxxxxOOO 
;    TTTTT           TTTTT
; MIN = Playfield left edge normal
; MAX = Playfield right edge - 5
;
PADDLE_NORMAL_MIN_X = PLAYFIELD_LEFT_EDGE_NORMAL-3
PADDLE_NORMAL_MAX_X = PLAYFIELD_RIGHT_EDGE_NORMAL-5

PADDLE_SMALL_MIN_X = PLAYFIELD_LEFT_EDGE_NORMAL
PADDLE_SMALL_MAX_X = PLAYFIELD_RIGHT_EDGE_NORMAL-5

; FYI:
; PLAYFIELD_LEFT_EDGE_NORMAL  = $30 ; First/left-most color clock horizontal position
; PLAYFIELD_RIGHT_EDGE_NORMAL = $CF ; Last/right-most color clock horizontal position

;  Offset to make binary 0 to 9 into text  
; 48 for PETSCII/ATASCII,  16 for Atari internal
NUM_BIN_TO_TEXT = 16  

; Adjusted playfield width for exaluating paddle position.
; This is needed several times, so is computed once here:
; Screen max X limit is 
; PLAYFIELD_RIGHT_EDGE_NORMAL/$CF -  PLAYFIELD_LEFT_EDGE_NORMAL/$30 == $9F
; Then, this needs to subtract 11 (12-1) for the size of the paddle, == $93.
PADDLE_MAX = (PLAYFIELD_RIGHT_EDGE_NORMAL-PLAYFIELD_LEFT_EDGE_NORMAL-11)


;===============================================================================
;    PAGE ZERO VARIABLES
;===============================================================================
; These will be used when needed to pass extra parameters to 
; routines when you can't use A, X, Y registers for other reasons.
; Essentially, think of these as extra data registers.
;
; Also used as permanent variables with lower latency than regular memory.
;
; The Atari OS has defined purpose for the first half of Page Zero 
; locations.  Since no Floating Point will be used here we'll 
; borrow everything in the second half of Page Zero.
;
;===============================================================================
;
; This list is a disorganized, royal mess.  Next time don't start 
; with the page zero list allowed for BASIC.  Just start at $80 and 
; run straight until $FF.
;
; Zero Page fun.  This is assembly, dude.  No BASIC in sight anywhere.
; No BASIC means we can get craaaazy with the second half of Page Zero.
;
; In fact, there's no need to have the regular game variables out in high memory.  
; All the Byte-sized values are hereby moved to Page 0.
;
;===============================================================================

PARAM_00 = $D4 ; ZMR_ROBOTO  -- Is Mr Roboto playing the automatic demo mode? init 1/yes
PARAM_01 = $D6 ; ZDIR_X      -- +1 Right, -1 Left.  Indicates direction of travel.
PARAM_02 = $D7 ; ZDIR_Y      -- +1 Down, -1 Up.  Indicates direction of travel.

PARAM_06 = $DC ; V_TEMP_ROW   -- VBI: Temporary Boom Block Row
PARAM_07 = $DD ; V_TEMP_CYCLE -- VBI: Temporary Boom Block Cycle

PARAM_09 = $80 ; TITLE_STOP_GO - set by mainline to indicate title is working or not.

PARAM_10 = $81 ; TITLE_PLAYING - flag indicates title animation stage in progress. 
PARAM_11 = $82 ; TITLE_TIMER - set by Title handler for pauses.
PARAM_12 = $83 ; TITLE_HPOSP0 - Current P/M position of fly-in letter. or 0 if no letter.
PARAM_13 = $84 ; TITLE_SIZEP0 - current size of Player 0
PARAM_14 = $85 ; TITLE_GPRIOR - Current P/M Priority in title. 
PARAM_15 = $86 ; TITLE_VSCROLL - current fine scroll position. (0 to 7)
PARAM_16 = $87 ; TITLE_CSCROLL - current coarse scroll position. (0 to 4)
PARAM_17 = $88 ; TITLE_CURRENT_FLYIN - current index (0 to 7) into tables for visible stuff in table below.
PARAM_18 = $89 ; TITLE_SCROLL_COUNTER - index into the tables above. 0 to 32
PARAM_19 = $8a ; TITLE_WSYNC_OFFSET - Number of scan lines to drop through before color draw

PARAM_20 = $8b ; TITLE_WSYNC_COLOR - Number of scan lines to do color bars
PARAM_21 = $8c ; TITLE_COLOR_COUNTER - Index into color table
PARAM_22 = $8d ; TITLE_DLI_PMCOLOR - PM Index into TITLE_DLI_PMCOLOR_TABLE
PARAM_23 = $8e ; THUMPER_PROXIMITY/THUMPER_PROXIMITY_TOP
PARAM_24 = $8f ; THUMPER_PROXIMITY_LEFT
PARAM_25 = $90 ; THUMPER_PROXIMITY_RIGHT
PARAM_26 = $91 ; THUMPER_FRAME/THUMPER_FRAME_TOP
PARAM_27 = $92 ; THUMPER_FRAME_LEFT
PARAM_28 = $93 ; THUMPER_FRAME_RIGHT
PARAM_29 = $94 ; THUMPER_FRAME_LIMIT/THUMPER_FRAME_LIMIT_TOP

PARAM_30 = $95 ; THUMPER_FRAME_LIMIT_LEFT
PARAM_31 = $96 ; THUMPER_FRAME_LIMIT_RIGHT
PARAM_32 = $97 ; THUMPER_COLOR/THUMPER_COLOR_TOP
PARAM_33 = $98 ; THUMPER_COLOR_LEFT
PARAM_34 = $99 ; THUMPER_COLOR_RIGHT
PARAM_35 = $9a ; BRICK_SCREEN_START_SCROLL
PARAM_36 = $9b ; BRICK_SCREEN_IMMEDIATE_POSITION
PARAM_37 = $9c ; BRICK_SCREEN_IN_MOTION
PARAM_38 = $9d ; ENABLE_BOOM
PARAM_39 = $9e ; ENABLE_BALL

PARAM_40 = $9f ; BALL_CURRENT_X
PARAM_41 = $a0 ; BALL_CURRENT_Y
PARAM_42 = $a1 ; BALL_HPOS
PARAM_43 = $a2 ; BALL_NEW_X
PARAM_44 = $a3 ; BALL_NEW_Y
PARAM_45 = $a4 ; BALL_COLOR
PARAM_46 = $a5 ; BALL_SPEED_CURRENT_SEQUENCE
PARAM_47 = $a6 ; BALL_SPEED_CURRENT_STEP
PARAM_48 = $a7 ; BALL_BOUNCE_COUNT
PARAM_49 = $a8 ; ENABLE_CREDIT_SCROLL - MAIN: Flag to stop/start scrolling/visible text

PARAM_50 = $a9 ; SCROLL_DO_FADE - MAIN: 0 = no fade.  1= fade up.  2 = fade down.
PARAM_51 = $aa ; SCROLL_TICK_DELAY - MAIN: number of frames to delay per scroll step.
PARAM_52 = $ab ; SCROLL_BASE - MAIN: Base table to start scrolling
PARAM_53 = $ac ; SCROLL_MAX_LINES - MAIN: number of lines in scroll before restart.
PARAM_54 = $ad ; SCROLL_CURRENT_TICK - VBI: Current tick for delay, decrementing to 0.
PARAM_55 = $ae ; SCROLL_IN_FADE - VBI: fade is in progress? 0 = no. 1 = up. 2 = down
PARAM_56 = $af ; SCROLL_CURRENT_FADE - VBI/DLI: VBI set for DLI - Current Fade Start position
PARAM_57 = $b0 ; SCROLL_CURRENT_LINE - VBI: increment for start line of window.
PARAM_58 = $b1 ; SCROLL_CURRENT_VSCROLL -  VBI/DLI: VBI sets for DLI -- Current Fine Vertical Scroll vertical position. 
PARAM_59 = $b2 ; ENABLE_PADDLE

PARAM_60 = $b3 ;   PADDLE_SIZE
PARAM_61 = $b4 ;   PADDLE_HPOS
PARAM_62 = $b5 ;   PADDLE_STRIKE
PARAM_63 = $b6 ;   PADDLE_FRAME
PARAM_64 = $b7 ;   PADDLE_STRIKE_COLOR
PARAM_65 = $b8 ; ENABLE_BALL_COUNTER
PARAM_66 = $b9 ;   BALL_COUNTER
PARAM_67 = $ba ;   BALL_TITLE_HPOS - DLI: Add 8 for PM1 and then same for PM2
PARAM_68 = $bb ;   SINE_WAVE_DELAY
PARAM_69 = $bc ;   BALL_COUNTER_COLOR

PARAM_70 = $bd ; ENABLE_SCORE
PARAM_71 = $be ;   REAL_SCORE_DIGITS
PARAM_72 = $bf ;   DISPLAYED_SCORE_DELAY
PARAM_73 = $c0 ;   DISPLAYED_BALLS_SCORE_COLOR_INDEX
PARAM_74 = $c1 ; ENABLE_SOUND
PARAM_75 = $c2 ;   SOUND_CURRENT_VOICE
PARAM_76 = $c3 ; ZAUTO_NEXT
PARAM_77 = $c4 ; ZBRICK_COUNT  - init 112 (full screen of bricks)
PARAM_78 = $c5 ; ZBRICK_POINTS - init 0 - point value of brick to add to score.
PARAM_79 = $c6 ; ZBALL_COUNT   - init 5


;===============================================================================
PARAM_80 = $c7 ; TITLE_SLOW_ME_CLOCK - frame clock to slow title stages. 
;===============================================================================
PARAM_81 = $c8 ; TITLE_COLOR_COUNTER_CLOCK - frame clock to slow color gradient
PARAM_82 = $c9 ; ENABLE_THUMPER - should have thought of this earlier.

PARAM_83 = $ca ; ZCOLLISION  -- Is Brick present at tested location? 0 = no, 1 = yes
PARAM_84 = $cb ; ZBRICK_LINE -- coord_Y reduced to line 1-8
PARAM_85 = $cc ; ZBRICK_COL  -- coord_X reduced to brick number 1-14
PARAM_86 = $cd ; ZCOORD_Y    -- coord_Y for collision check
PARAM_87 = $ce ; ZCOORD_X    -- coord_X for collision check 
PARAM_88 = $cf ; V_15FPS_TICKER -- When this is 0, then 1/4 tick events occur.
PARAM_89 = $d0 ; M_TEMP1  -- local temporary value
PARAM_90 = $d1 ; DIAG_BRICK_Y - remember Y for looping brick destruction 
PARAM_91 = $d2 ; DIAG_BRICK_X - remember X for looping brick destruction
PARAM_92 = $d3 ; DIAG_SLOW_ME_CLOCK
PARAM_93 = $d5 ; DIAG_TEMP1

PARAM_94 = $D8 ; MAIN: Direction Index
PARAM_95 = $D9 ; MAIN: Speed Index
PARAM_96 = $DA ; MAIN: Delay Index
PARAM_97 = $DB ; MAIN: Temporary SAVE/PHA


PARAM_98 = $DE ; V_20FPS_TICKER -- When this is 0, then 1/3 tick events occur.
PARAM_99 = $DF ; V_30FPS_TICKER -- When this is 0, then 1/2 tick events occur

PARAM_AA = $E0 ; V_TEMP -- Misc counter for boom bricks
PARAM_AB = $E1


ZEROPAGE_POINTER_3 = $E2 ; 
ZEROPAGE_POINTER_4 = $E4 ; 
ZEROPAGE_POINTER_5 = $E6 ;
ZEROPAGE_POINTER_6 = $E8 ;
ZEROPAGE_POINTER_7 = $EA ; ZTEMP_PMADR   -- VBI uses for boom block image target 
ZEROPAGE_POINTER_8 = $EC ; ZBRICK_BASE   -- Pointer to start of bricks on a line.
ZEROPAGE_POINTER_9 = $EE ; ZTITLE_COLPM0 -- VBI sets for DLI to use



;===============================================================================
;   DECLARE VALUES AND ADDRESS ASSIGNMENTS (NOT ALLOCATING MEMORY)
;===============================================================================

ZMR_ROBOTO =  PARAM_00 ; Is Mr Roboto playing the automatic demo mode? init 1/yes

ZDIR_X =      PARAM_01 ; +1 Right, -1 Left.  Indicates direction of travel.
 
ZDIR_Y =      PARAM_02 ; +1 Down, -1 Up.  Indicates direction of travel.


ZCOLLISION =  PARAM_83 ; Is Brick present at tested location? 0 = no, 1 = yes

ZBRICK_LINE = PARAM_84 ; Ycoord reduced to line 1-8

ZBRICK_COL =  PARAM_85 ; Xcoord reduced to brick number 1-14

ZCOORD_Y =    PARAM_86 ; Ycoord for collision check

ZCOORD_XP =   PARAM_87 ; Xcoord for collision check  


V_15FPS_TICKER = PARAM_88 ; count 0, 1, 2, 3, 0, 1, 2, 3... 0 triggers animation events.

V_20FPS_TICKER = PARAM_98 ; count 0, 1, 2, 0, 1, 2... 0 triggers animation events.

V_30FPS_TICKER = PARAM_99 ; count 0, 1, 0, 1... 0 triggers animation events.

; flag when timer counted (29 sec). Used on the
; title and game over  and auto play screens. When auto_wait
; ticks it triggers automatic transition to the 
; next screen.
ZAUTO_NEXT =    PARAM_76 ; .byte 0

ZBRICK_COUNT =  PARAM_77 ; .byte 112 (full screen of bricks, 8 * 14)

ZBRICK_POINTS = PARAM_78 ; .byte $00

ZBALL_COUNT =   PARAM_79 ; .byte $05


ZTEMP_PMADR =   ZEROPAGE_POINTER_7 ; $EA - VBI uses for boom block image target 

ZBRICK_BASE =   ZEROPAGE_POINTER_8 ; $EC - Pointer to start of bricks on a line.

ZTITLE_COLPM0 = ZEROPAGE_POINTER_9 ; $EE - VBI sets for DLI to use


V_TEMP_ROW =   PARAM_06 ; = $DC ; -- VBI: Temporary Boom Block Row
V_TEMP_CYCLE = PARAM_07 ; = $DD ; -- VBI: Temporary Boom Block Cycle

V_TEMP = PARAM_AA ; $E0 -- VBI: temp counter for boom blocks

M_DIRECTION_INDEX = PARAM_94 ; = $D8 ; MAIN: Direction Index
M_SPEED_INDEX =     PARAM_95 ; = $D9 ; MAIN: Speed Index
M_DELAY_INDEX =     PARAM_96 ; = $DA ; MAIN: Delay Index
M_TEMP_PHA =        PARAM_97 ; = $DB ; MAIN: Temporary SAVE/PHA

M_TEMP1 = PARAM_89 ; = $d0 ;   -- local temporary value


;===============================================================================
; ****    ******   ****   *****   **        **    **  **   ****
; ** **     **    **      **  **  **       ****   **  **  **  **
; **  **    **     ****   **  **  **      **  **   ****   ** ***
; **  **    **        **  *****   **      **  **    **    *** **
; ** **     **        **  **      **      ******    **    **  **
; ****    ******   ****   **      ******  **  **    **     ****
;===============================================================================

;===============================================================================
; MOVING PARTS
;===============================================================================

; DISPLAY values using Page 0 locations.

;ZROW_LMS0 = ZEROPAGE_POINTER_0 ; Pointer to display list LMS brick row 0
;ZROW_LMS1 = ZEROPAGE_POINTER_1 ; Pointer to display list LMS brick row 0
;ZROW_LMS2 = ZEROPAGE_POINTER_2 ; Pointer to display list LMS brick row 0
;ZROW_LMS3 = ZEROPAGE_POINTER_3 ; Pointer to display list LMS brick row 0
;ZROW_LMS4 = ZEROPAGE_POINTER_4 ; Pointer to display list LMS brick row 0
;ZROW_LMS5 = ZEROPAGE_POINTER_5 ; Pointer to display list LMS brick row 0
;ZROW_LMS6 = ZEROPAGE_POINTER_6 ; Pointer to display list LMS brick row 0
;ZROW_LMS7 = ZEROPAGE_POINTER_7 ; Pointer to display list LMS brick row 0

; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.

;===============================================================================
; BRICKS/PLAYFIELD -- HORIZONTAL SCROLL
;===============================================================================
; The playfield area is used for the game bricks while playing 
; and the large blocks for the TITLE LOGO and the GAME OVER.
;
; Lets talk about horizontal fine scrolling on the Atari...
;
; Earlier, the BRICK_LINEs were defined as 64-bytes each. 
; Part of the reason for this is to make the address math easy
; for the rows.   The other part has to do with how horizontal
; scrolling works.
;
; The graphics mode for the BRICKS is 20 bytes for normal screen 
; width (at 8 color clocks per byte). The game needs three screens 
; next to each other to accommodate the transitions.  (Well, it 
; could actually be done as 2 screens next to each other by someone 
; more clever. It is easier for my feeble mind to manage it if the 
; apparent transition motion between three screens really is 
; three screens.)
;
; The screen arrangement per line:
; 20 bytes|20 bytes|20 bytes == 60 bytes.
;
; To make the screens look like the end of one screen isn't 
; directly attached to the start of the next, I insert
; one empty byte between each:
; 20 bytes|1 byte|20 bytes|1 byte|20 bytes == 62 bytes.
;
; So, the program can just use the first 62 bytes of each row, and
; ignore the last two, right? Not so. The program must offset its 
; base reference for the three screens due to the way the Atari 
; does horizontal scrolling. 
;
; When horizontal scrolling is enabled ANTIC reads more data beginning
; at the current memory scan address than it needs to display the
; visible graphics line -- it reads enough additional data to 
; maintain a buffer of 16 color clocks at the beginning of the 
; display line.
;
; Examples below assume a graphics mode that displays 8 color clocks 
; (pixels) per byte (the mode used for the game playfield.):
;
; Normal memory read and display:
; (Simple and obvious -- 20 bytes read. 20 bytes displayed) 
; P is displayed pixels from a byte
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3 ...|byte 18 |byte 19 |
; |PPPPPPPP|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|
; 
; Memory read and display for Horizontal scrolling:
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|
;   FEDCBA9|87654321|0 = HSCROL positions
;                    ^ HSCROL = 0
;
; Horizontal scrolling works by using the HSCROL register to specify
; how many of the 16 buffered color clocks at the start of the line 
; should be output for display.  The example above shows none of the 
; buffered pixels output, so the HSCROL value is 0. Note that in this 
; case of HSCROL value 0 the buffer causes the actual display output to 
; begin two bytes later in memory than specified by ANTIC's memory scan 
; pointer.  

; The HSCROL value may range from 0 buffered color clocks output to 
; display up to 15 buffered color clocks output.  The example below 
; shows HSCROL set to 3.
;
; Memory read and display for Horizontal scrolling when HSCROL = 3
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPNNN|
;   FEDCBA9|87654321|0 = HSCROL positions
;                ^ HSCROL = 3
;
; The number of color clocks output for display is still consistent with the 
; normal output for the mode of graphics.   The contents of the line 
; shifts to the right "losing" 3 color clocks at the right side of the screen
; while HSCROL adds 3 color clocks to the left side of the display.
;
; Note that while ANTIC buffers 16 color clocks of data, the HSCROL value can 
; only range up to 15.  This means the first buffered color clock is not
; displayable...
;
; Memory read and display for Horizontal scrolling when HSCROL = 15 ($F)
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BDDDDDDD|DDDDDDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PNNNNNNN|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; | ^ HSCROL = 15 ($F)
;  
; Displaying that final color clock requires (at least) one more byte prior 
; to this byte allowing HSCROL to output the contents of this byte.
; In other words, begin displaying from a previous memory location 
; (the original byte 0 address - 2 bytes) and then set fine scroll HSCROL 
; value to 0.
;
; An interesting part of Atari horizontal scrolling is that the 16 color 
; clocks buffered can exceed the distance of one byte's worth of color clocks.
; Therefore the increment (or decrement) for coarse scrolling is greater than 
; 1 byte. Some ANTIC modes have two bytes per 16 color clocks, some have 
; 4 bytes.  This has the interesting effect that the same display can be output 
; by different variations of memory scan starting address and HSCROL.
; For example, the display output is identical for the two settings below:
; 
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is pixels not displayed on right.
; Z is pixels not read/not buffered/not displayed from the left 
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 0
;
; MS (memory scan pointer points to byte 1)
;           v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |ZZZZZZZZ|BBBBBBBB|DDDDDDDD|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; |        | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 8
;
; So, the consequence of this discussion and horizontal scrolling's treatment of the 
; first byte of the buffer means that the program can't consider the first byte 
; completely displayable and will ignore it as part of the intended display output.  
; However, the program must still accommodate that byte in order to scroll to the 
; byte that follows. 
;
; Therefore, the memory map for the display lines looks like this: 
; ignore byte 0|20 bytes|1 byte|20 bytes|1 byte|20 bytes == 63 bytes.
;
; Thus the origination position for each of the three screens relative to the 
; base address of each line:
; Left Screen: Memory Scan +0,  HSCROL = 8
; Center Screen: Memory Scan +20, HSCROL = 0 (or Memory Scan +21, HSCROL = 8)
; Right Screen: Memory Scan +41, HSCROL = 0 (or Memory Scan +42, HSCROL = 8)
;
; Reference lookup for Display List LMS offset for screen postition:
; 0 = left
; 1 = center
; 2 = right
;
;
; MAIN flag to VBI requesting start of screen transition.
;
BRICK_SCREEN_START_SCROLL = PARAM_35
; .byte 0
;
; MAIN signal to move immediately to target positions if value is 1.
; Copy the BRICK_BRICK_SCREEN_TARGET_LMS_LMS and 
; BRICK_SCREEN_TARGET_HSCROL to all current positions.
;
BRICK_SCREEN_IMMEDIATE_POSITION = PARAM_36
; .byte 0
;
; VBI Feedback to MAIN that it is busy moving
;
BRICK_SCREEN_IN_MOTION = PARAM_37
; .byte 0
;



;===============================================================================
; ****   ******   **    *****   ****
; ** **    **    ****  **      **  **
; **  **   **   **  ** **      ** ***
; **  **   **   **  ** ** ***  *** **
; ** **    **   ****** **  **  **  **
; ****   ****** **  **  *****   ****
;===============================================================================

DIAG_SLOW_ME_CLOCK = PARAM_92 ; = $d3 ; DIAG_SLOW_ME_CLOCK

DIAG_TEMP1 = PARAM_93 ; = $d5 ; DIAG_TEMP1



;===============================================================================
;   INITIALIZE ZERO PAGE VALUES
;===============================================================================

    *= BRICK_SCREEN_START_SCROLL ; and BRICK_SCREEN_IMMEDIATE_POSITION and BRICK_SCREEN_IN_MOTION
    .byte 0,0,0
    

    





;===============================================================================
;   LOAD START
;===============================================================================

;	*=LOMEM_DOS     ; $2000  ; After Atari DOS 2.0s
;	*=LOMEM_DOS_DUP ; $3308  ; Alternatively, after Atari DOS 2.0s and DUP

; This will not be a terribly big or complicated game.  Begin after DOS/DUP.
; This will change in a moment when alignment is reset for Player/Missile memory.

	*= $3308    

;===============================================================================

;===============================================================================
;   DISPLAY RELATED MEMORY
;===============================================================================
; This defines several large blocks and repeatedly forces 
; (re)alignment to Page and K boundaries.
;

;   .include "display.asm"
;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================


;===============================================================================
; PLAYER/MISSILE BITMAP MEMORY
;===============================================================================

;	*=$8000

	*= [*&$F800]+$0800
	
; Using 2K boundary for single-line 
; resolution Player/Missiles
PLAYER_MISSILE_BASE
PMADR_MISSILE = [PLAYER_MISSILE_BASE+$300] ; Ball.                            Ball counter.
PMADR_BASE0 =   [PLAYER_MISSILE_BASE+$400] ; Flying text. Boom brick. Paddle. Ball Counter.
PMADR_BASE1 =   [PLAYER_MISSILE_BASE+$500] ;              Boom Brick. Paddle. Ball Counter.
PMADR_BASE2 =   [PLAYER_MISSILE_BASE+$600] ; Thumper.                 Paddle. Ball Counter.
PMADR_BASE3 =   [PLAYER_MISSILE_BASE+$700] ; Thumper.                 Paddle. Ball Counter.

; Align to the boundary after Player/missile bitmaps
; ( *= $8800 )
	*= [*&$F800]+$0800

; Custom character set for Credit text window
; Mode 3 Custom character set. 1024 bytes
; Alphas, numbers, basic punctuation.
; - ( ) . , : ; and /
; Also, infinity and Cross.
; Also artifact "FIRE"

; Character set is 1K of data, so alignment does 
; not need to be forced here.
; ( *= $8C00 )
CHARACTER_SET_00
	.incbin "mode3.cset"


; Custom character set for Title and Score
; Mode 6 custom character set.  512 bytes.
; 2x chars for 0 to 9. 1-10 (top) and 11-20 (bottom)
; 2x chars for title text:  
; B R E A K O U T $15-$24 (top/bottom interleaved)
; 3 chars for ball counter label "BALLS" ($25-$27)

; Character set is 1/2K of data, so
; alignment does not need to be forced here.
; ( *= $8E00 )
CHARACTER_SET_01
	.incbin "breakout.cset"



;===============================================================================
; SCREEN MEMORY -- Directly displayed memory
;===============================================================================

; ( *= $8C00 to $8DFF )
; Real Playfield Memory:  2 pages.
; Aligning inside page boundaries means
; scrolling will only need to update the 
; LMS low byte for every line
;


BRICK_LINE0 
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0000
BRICK_LINE1
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0040
BRICK_LINE2
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0080
BRICK_LINE3
	.ds $40 ; 64 bytes for left/right scroll. Relative +$00C0
BRICK_LINE4
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0100
BRICK_LINE5
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0140
BRICK_LINE6
	.ds $40 ; 64 bytes for left/right scroll. Relative +$0180
BRICK_LINE7
	.ds $40 ; 64 bytes for left/right scroll. Relative +$01C0




; ( *= $8F00 to $8F3F )
; Master copies (source copied to working screen)
;
EMPTY_LINE ; 64 bytes of 0.
	.ds $40 ; 64 bytes of 0.                  Relative +$0200






	
	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DIAG0
;	.sbyte " JF SS SI VM H0 H1 H2 H3 H4    DE SP DI "
	.sbyte " JF EB    RQ    RB CY BB HP SZ CP       "

DIAG1
	.dc 40 $00
	


;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================

;===============================================================================
; NOT SCREEN MEMORY (parts copied to screen RAM)
;===============================================================================


; ( *= $8F54 to $8F67 ) 20 bytes
; 14 bricks, 11 pixels each, 154 pixels total. 
; Centered in 160 pixels.
; Bricks start at pixel 3 (counting from 0.
; Its easier to figure this out drawing it in binary...
;
BRICK_LINE_MASTER
	.byte ~00011111, ~11111011, ~11111111, ~01111111, ~11101111 ; 0, 1, 2, 3
	.byte ~11111101, ~11111111, ~10111111, ~11110111, ~11111110 ; 3, 4, 5, 6
	.byte ~11111111, ~11011111, ~11111011, ~11111111, ~01111111 ; 7, 8, 9, 10
	.byte ~11101111, ~11111101, ~11111111, ~10111111, ~11110000 ; 10, 11, 12, 13
	

; I want the graphics masters aligned to the start of a page.
; to insure cycling between each line does not require 
; updating a high byte for address.
	*=[*&$FF00]+$0100
	
; ( *= $9000 )  ( 20 bytes  * 8 lines == 160 bytes ) 
; Logo Picture imitating bricks.  
; Conveniently, 4 pixels/nybble per brick.
; Originally the graphic was 38 Characters wide,
; now as nybble pairs it is 19 characters wide. 
; In order to center this in the Playfield, each
; line is shifted one nybble, to center the data
; in 20 bytes.
;
; ***  ***  **** **   *  * **** *  *I***
; *  * *  * *    * *  *  * *  * *  *  * 
; *  * *  * *    *  * * *  *  * *  *  * 
; ***  ***  ***  **** ***  *  * *  *  * 
; *  * *  * *    *  * *  * *  * *  *  * 
; ** * ** * **   ** * ** * ** * ** *  **
; ** * ** * **   ** * ** * ** * ** *  **
; ***  ** * **** ** * ** * **** ****  **
;
LOGO_LINE0
	.byte $0F,$FF,$00,$FF,$F0,$0F,$FF,$F0,$FF,$00,$0F,$00,$F0,$FF,$FF,$0F,$00,$F3,$FF,$F0
LOGO_LINE1
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$F0,$0F,$00,$F0,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE2
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$0F,$0F,$0F,$00,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE3
	.byte $0F,$FF,$00,$FF,$F0,$0F,$FF,$00,$FF,$FF,$0F,$FF,$00,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE4
	.byte $0F,$00,$F0,$F0,$0F,$0F,$00,$00,$F0,$0F,$0F,$00,$F0,$F0,$0F,$0F,$00,$F0,$0F,$00
LOGO_LINE5
	.byte $0F,$F0,$F0,$FF,$0F,$0F,$F0,$00,$FF,$0F,$0F,$F0,$F0,$FF,$0F,$0F,$F0,$F0,$0F,$F0
LOGO_LINE6
	.byte $0F,$F0,$F0,$FF,$0F,$0F,$F0,$00,$FF,$0F,$0F,$F0,$F0,$FF,$0F,$0F,$F0,$F0,$0F,$F0
LOGO_LINE7
	.byte $0F,$FF,$00,$FF,$0F,$0F,$FF,$F0,$FF,$0F,$0F,$F0,$F0,$FF,$FF,$0F,$FF,$F0,$0F,$F0


; I want the graphics masters aligned to the start of a page.
; to insure cycling between each line does not require 
; updating a high byte for address.
	*=[*&$FF00]+$0100

; ( *= $9100 )  ( 20 bytes  * 8 lines == 160 bytes )

; Game Over Picture imitating bricks.  3 pixels per brick,
; because it would not fit with 4 pixels per block.  At 4 pixels
; per brick the text would be 42 blocks which is 168 pixels and 
; the limit is 160 pixels in this mode.  
;
; This is redrawn and reencoded. Converting the picture 
; blocks to 000 or 111 bits worked well, so the representation 
; here is bit format. This is now 3 pixels * 42 block
; which is 126 pixels. Two additional 0 bits added to 
; center this in 128 pixels. Graphics length is 16 bytes.
; two 0 bytes added to the beginning and end of each line
; to center this in 20 bytes.
; 
; **** **   *   * ****   **** *  * **** *** 
; *    * *  ** ** *      *  * *  * *    *  *
; *    *  * * * * *      *  * *  * *    *  *
; * ** **** *   * ***    *  * *  * ***  *** 
; *  * *  * *   * *      *  * *  * *    *  *
; ** * ** * **  * **     ** * ** * **   ** *
; ** * ** * **  * **     ** *  * * **   ** *
; ***  ** * **  * ****   ****   ** **** ** *
;

GAMEOVER_LINE0
	.byte $00,$00,~01111111,~11111000,~11111100,~00000001,~11000000,~00011100,~01111111,~11111000,~00000011,~11111111,~11000111,~00000011,~10001111,~11111111,~00011111,~11110000,$00,$00
GAMEOVER_LINE1
	.byte $00,$00,~01110000,~00000000,~11100011,~10000001,~11111000,~11111100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE2
	.byte $00,$00,~01110000,~00000000,~11100000,~01110001,~11000111,~00011100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE3
	.byte $00,$00,~01110001,~11111000,~11111111,~11110001,~11000000,~00011100,~01111111,~11000000,~00000011,~10000001,~11000111,~00000011,~10001111,~11111000,~00011111,~11110000,$00,$00
GAMEOVER_LINE4
	.byte $00,$00,~01110000,~00111000,~11100000,~01110001,~11000000,~00011100,~01110000,~00000000,~00000011,~10000001,~11000111,~00000011,~10001110,~00000000,~00011100,~00001110,$00,$00
GAMEOVER_LINE5
	.byte $00,$00,~01111110,~00111000,~11111100,~01110001,~11111000,~00011100,~01111110,~00000000,~00000011,~11110001,~11000111,~11100011,~10001111,~11000000,~00011111,~10001110,$00,$00
GAMEOVER_LINE6
	.byte $00,$00,~01111110,~00111000,~11111100,~01110001,~11111000,~00011100,~01111110,~00000000,~00000011,~11110001,~11000000,~11100011,~10001111,~11000000,~00011111,~10001110,$00,$00
GAMEOVER_LINE7
	.byte $00,$00,~01111111,~11000000,~11111100,~01110001,~11111000,~00011100,~01111111,~11111000,~00000011,~11111111,~11000000,~00011111,~10001111,~11111111,~00011111,~10001110,$00,$00








	

; A VBI sets initial values:
; HPOS and SIZE for all Players and missiles.
; HSCROL and VSCROL.
; By default CHBAS and inital COLPF/COLPM are already handled.

;===============================================================================
; DISPLAY DESIGN 
;===============================================================================

;-------------------------------------------
; TITLE SECTION: NARROW
; Player 0 == Flying text.
; Mode 6 color text for title.
; Color 0 == Text
; Color 1 == Text
; Color 2 == Text
; Color 3 == Text
;-------------------------------------------
; COLPM0, COLPF0, COLPF1, COLPF2, COLPF3
; HPOSP0
; SIZEP0
; CHBASE
; VSCROLL, HSCROLL (for centering)
;-------------------------------------------
	; Scan line 8,       screen line 1,         One blank scan line

; Jump to Title Scroll frame...

	; Scan lines 9-41,   screen lines 2-34,     4 lines of Mode 6 text for vertical scrolling title 

; Jump back to Main list.

;-------------------------------------------
; THUMPER BUMPER SECTION: NORMAL
; color 1 = horizontal/top bumper.
; Player 3 = Left bumper 
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF0, COLPM3, COLPM2
; HPOSP3, HPOSP2
; SIZEP3, SIZEP2
;-------------------------------------------

	; Scan line 42,      screen line 35,         One blank scan lines

; Jump to Horizontal Thumper bumper

	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine

; Jump back to Main list.

;-------------------------------------------
; PLAYFIELD SECTION: NORMAL
; color 1 = bricks
; Missile 3 (5th Player) = BALL 
; Player 0 = boom-o-matic animation 1
; Player 1 = boom-o-matic animation 1
;-------------------------------------------
;    and already set earlier:
; Player 3 = Left bumper 
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF0, COLPM0, COLPM1, COLPF3
; HPOSP0, HPOSP1, HPOSM3
; SIZEP0, SIZEP1, SIZEM3
; VSCROLL
;-------------------------------------------

; Blanks above bricks.

	; Scan line 54-77,   screen line 47-70,     24 blank lines

; Bricks...
	; Scan line 78-82,   screen line 71-75,     5 Mode C lines, repeated
	; Scan line 83-84    screen line 76-77,     Two blank scan lines, No scrolling -- sacrifice line
	; ...
	; Brick line 8
	; Scan line 127-131, screen line 120-124,   5 Mode C lines, repeated
	; Scan line 132-133, screen line 125-126,   Two blank scan lines, No scrolling -- sacrifice line

; After Bricks.
	; Scan line 134-141, screen line 127-134,   Eight blank scan lines

;-------------------------------------------
; CREDITS SECTION: NARROW
; Color 2 = text
; Color 3 = text background
;    and already set earlier:
; Missile 3 (5th Player) = Ball
; Player 3 = Left bumper 
; Player 2 = Right Bumper
;-------------------------------------------
; COLPF1, COLPF2
; CHBASE
; VSCROLL, HSCROLL
;-------------------------------------------

; Credits
	; Scan line 142-151, screen line 135-144,   10 Lines Mode 3
	; Scan line 152-161, screen line 145-154,   10 Lines Mode 3
	; Scan line 162-171, screen line 155-164,   10 Lines Mode 3
	; Scan line 172-181, screen line 165-174,   10 Lines Mode 3
	; Scan line 182-191, screen line 175-184,   10 Lines Mode 3
	; Scan line 192-201, screen line 185-194,   10 Lines Mode 3
	; Scan line 202-202, screen line 195-195,   10 (1) Lines Mode 3 ; scrolling sacrifice
	
	; Scan line 203-204, screen line 196-197,   Two blank scan lines

;-------------------------------------------
; PADDLE SECTION: NARROW
; Player 1 = Paddle
; Player 2 = Paddle
; Player 3 = Paddle
;    and already set earlier:
; Missile 3 (5th Player) = BALL
;-------------------------------------------
; COLPM1, COLPM2, COLPM3
;-------------------------------------------

; Paddle
	; Scan line 205-212, screen line 198-205,   Eight blank scan lines (top 4 are paddle)	

;-------------------------------------------
; SCORE SECTION: NORMAL
; Player 0 == Sine Wave Balls
; Player 1 == Sine Wave Balls
; Player 2 == Sine Wave Balls.
; Player 3 == Sine Wave Balls
; Missile 3 == Sine Wave Balls
; Mode 6 color text for score.
; Color 1  == "BALLS" 
; Color 2  == score
; Color 3  == score
;-------------------------------------------
; COLPM0, COLPF0, COLPF1, COLPF2, COLPF3
; HPOSP0, HPOSP1, HPOSP2, HPOSP3, 
; HPOSM0, HPOSM1, HPOSM2, HPOSM3 
; SIZEP0, SIZEP1, SIZEP2, SIZEP3, SIZEM
; CHBASE
; HSCROLL?
;-------------------------------------------
; Ball counter and score
	; Scan line 213-220, screen line 206-213,   Mode 6 text, scrolling
	; Scan line 221-228, screen line 214-221,   Mode 6 text, scrolling

	; Scan line 229-229, screen line 222-222,   One blank scan line
	
; Jump Vertical Blank.



;===============================================================================
; Forcing the Display list to a 1K boundary 
; is mild overkill.  Display Lists even as funky
; as this one are fairly short. 
; Alignment to the next 256 byte Page is sufficient insurance 
; preventing the display list from crossing over 
; the next 1K boundary.

	*=[*&$FF00]+$0100

	; ( *= $9300 to  ) 

DISPLAY_LIST 
 
	; Scan line 8,       screen line 1,         One blank scan line
	.byte DL_BLANK_1|DL_DLI 
	; VBI: Set Narrow screen, HSCROLL=4 (to center text), VSCROLL, 
	;      HPOSP0 and SIZE0 for title.  PRIOR=All P/M on top.
	; DLI1: hkernel for COLPF and COLPM color bars in the text.

;===============================================================================

;	.byte DL_JUMP		    ; JMP to Title scrolling display list "routine"

;DISPLAY_LIST_TITLE_VECTOR   ; Low byte of coarse scroll frame
;	.word TITLE_FRAME_EMPTY ; 

;TITLE_FRAME_EMPTY
; Scan line 9-16,    screen lines 2-9,      Eight blank lines
	.byte DL_BLANK_8
; Scan line 17-24,   screen lines 10-17,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 25-32,   screen lines 18-25,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 33-40,   screen lines 26-33,    Eight blank lines
	.byte DL_BLANK_8
; Scan line 41,      screen lines 34,       1 blank lines, (mimic the scrolling sacrifice)
	.byte DL_BLANK_1|DL_DLI ; DLI2 for Horizontal Thumper Bumper
; Return to main display list
;	.byte DL_JUMP
;	.word DISPLAY_LIST_TITLE_RTS

;===============================================================================

	; DLI2: Occurred as the last line of the Title SCroll section.
	; Set Normal Screen, VSCROLL=0, COLPF0 for horizontal bumper.
	; Set PRIOR for Fifth Player.
	; Set HPOSM0/HPOSM1, COLPF3 SIZEM for left and right Thumper-bumpers.
	; set HITCLR for Playfield.
	; Set HPOSP0/P1/P2, COLPM0/PM1/PM2, SIZEP0/P1/P2 for top row Boom objects.
	
;DISPLAY_LIST_TITLE_RTS ; return destination for title scrolling "routine"
	; Scan line 42,      screen line 35,         One blank scan lines
	.byte DL_BLANK_1   ; I am uncomfortable with a JMP going to a JMP.
	; Also, the blank line provides time for clean DLI.
		
	; Scan lines 43-53,  screen line 36-46,     11 various blank and graphics lines in routine

	
;	.byte DL_JUMP	        ; Jump to horizontal thumper animation frame
DISPLAY_LIST_THUMPER_VECTOR ; remember this -- update low byte to change frames
;	.word THUMPER_FRAME_WAIT

;   Simulate the thumper box.

    .byte DL_BLANK_3
    .byte DL_BLANK_8
    
	; Note DLI started before thumper-bumper Display Lists for 
	; P/M HPOS, COLPM, SIZE and HITCLR
	; Also, this DLI ends by setting HPOS and COLPM for the BOOM 
	; objects in the top row of bricks. 

DISPLAY_LIST_THUMPER_RTS ; destination for animation routine return.
	; Top of Playfield is empty above the bricks. 
	; Scan line 54-77,   screen line 47-70,     24 blank lines


	.byte DL_BLANK_8
	.byte DL_BLANK_8
;	.byte DL_BLANK_7|DL_DLI 


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; DIAGNOSTIC ** START
	; Delineate end of DLI VSCROLL area
	.byte DL_BLANK_5  ; 5 + 1 mode C below + 1 blank below = 7 commented above
	.byte DL_MAP_C|DL_LMS
	.word BRICK_LINE_MASTER 	
; DIAGNOSTIC ** END


	.byte DL_BLANK_1|DL_DLI
	 
	.byte DL_BLANK_1
	
	; DLI3: Hkernel 8 times....
	;      Set HSCROLL for line, VSCROLL = 5, then Set COLPF0 for 5 lines.
	;      Reset VScroll to 1 (allowing 2 blank lines.)
	;      Set P/M Boom objects, HPOS, COLPM, SIZE
	;      Repeat HKernel.

	; Define 8 rows of Bricks.  
	; Each is 5 lines of mode C graphics, plus 2 blank line.
	; The 5 rows of graphics are defined by using the VSCROL
	; exploit to expand one line of mode C into five lines.

	; Block line 1
	; Scan line 78-82,   screen line 71-75,     5 Mode C lines, repeated
	; Scan line 83-84    screen line 76-77,     Two blank scan lines, No scrolling -- sacrifice line
	; ...
	; Block line 8
	; Scan line 127-131, screen line 120-124,   5 Mode C lines, repeated
	; Scan line 132-133, screen line 125-126,   Two blank scan lines, No scrolling -- sacrifice line
DL_BRICK_BASE
	; DL_BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.
	; Only this byte should be needed for scrolling each row.

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE0+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE1+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	
	
	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE2+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE3+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	
	

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE4+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE5+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	
	
	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE6+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	

	; scan line +0 to +4  -- 5 scan lines of mode C copied/extended
	.byte DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
	.word [BRICK_LINE7+21] ; offset into center screen
	; two blank scan line
	.byte DL_BLANK_2 	
	
	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; DIAGNOSTIC ** START	
; Temporarily test layout and spacing without the DLI/VSCROL trickery.

;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
;	.byte DL_MAP_C|DL_LMS|DL_HSCROLL
;	.word BRICK_LINE0+[entry*$40] ; not immediately offset into middle of graphics line
;	.word [GAMEOVER_LINE0+[entry*20]-2]
; DIAGNOSTIC ** END

	; HKernel ends:
	; set Narrow screen, COLPF2, VSCROLL, COLPF1 for scrolling credit/prompt window.
	; Collect HITCLR values for analysis of bricks .  Reset HITCLR.
	
	
	; a scrolling window for messages and credits.  
	; This is 8 blank lines +  8 * 10 scan lines plus 7 blank lines.
	; These are ANTIC Mode 3 lines so each is 10 scan lines tall.


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

	; Delineate end of Bricks/VSCROLL area

	.byte DL_MAP_C|DL_LMS
	.word BRICK_LINE_MASTER 	


	
; some blank lines, two lines diagnostics, a few more blank lines.


	.byte DL_BLANK_8,DL_BLANK_8,DL_BLANK_7|DL_DLI; This is last DLI for DIAG
	.byte DL_BLANK_8 
	.byte DL_TEXT_2|DL_LMS
	.word DIAG0
	.byte DL_BLANK_4
	.byte DL_TEXT_2|DL_LMS
	.word DIAG1
	.byte DL_BLANK_8,DL_BLANK_8,DL_BLANK_8,DL_BLANK_8

	
	
	
	
	; Finito.
	.byte DL_JUMP_VB
	.word DISPLAY_LIST


;===============================================================================
; ****    ******   ****   *****   **        **    **  **  
; ** **     **    **      **  **  **       ****   **  ** 
; **  **    **     ****   **  **  **      **  **   ****  
; **  **    **        **  *****   **      **  **    **   
; ** **     **        **  **      **      ******    **   
; ****    ******   ****   **      ******  **  **    **   
;===============================================================================

; Non-aligned variables and data.

;TEMP ; Need to come back here.

;	*=ZROW_LMS0 ; Create table of the addresses of the LMS instructions

;	entry .= 1
;	.rept 8
;		.word [DL_BRICK_BASE+entry] ; DL_BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29
;		entry .= entry+4
;	.endr
;		.word [DL_BRICK_BASE+5 ] ; Row 1 +5
;		.word [DL_BRICK_BASE+9 ] ; Row 2 +9
;		.word [DL_BRICK_BASE+13] ; Row 3 +13
;		.word [DL_BRICK_BASE+17] ; Row 4 +17
;		.word [DL_BRICK_BASE+21] ; Row 5 +21 
;		.word [DL_BRICK_BASE+25] ; Row 6 +25
;		.word [DL_BRICK_BASE+29] ; Row 7 +29

;	*=TEMP


	

; Game Modes.  
; Different sections of the screen are operating at different times.
; 0 = Main title screen.
;     SCrolling title text is OFF.
;     Thumper Bumpers are OFF.  (But they would be off by default over time).
;     BALL is OFF
;     Paddle is off.
; 

;===============================================================================
; ALL THE MOVING PARTS
;===============================================================================
; Tables of things previously declared.
; Tables that don't need alignment.
; Other variables for controlling action/animation and interaction 
; between the display, the VBI, and MAIN.

; Display List Interrupts, Internal Shadow data, and other information.
; Most of this is managed and indexed by the Vertical Blank Interrupt.
; The Display List and Display List Interrupt simply show it as presented.











; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.

;===============================================================================
; BRICKS/PLAYFIELD -- HORIZONTAL SCROLL
;===============================================================================
; The playfield area is used for the game bricks while playing 
; and the large blocks for the TITLE LOGO and the GAME OVER.
;
; Lets talk about horizontal fine scrolling on the Atari...
;
; Earlier, the BRICK_LINEs were defined as 64-bytes each. 
; Part of the reason for this is to make the address math easy
; for the rows.   The other part has to do with how horizontal
; scrolling works.
;
; The graphics mode for the BRICKS is 20 bytes for normal screen 
; width (at 8 color clocks per byte). The game needs three screens 
; next to each other to accommodate the transitions.  (Well, it 
; could actually be done as 2 screens next to each other by someone 
; more clever. It is easier for my feeble mind to manage it if the 
; apparent transition motion between three screens really is 
; three screens.)
;
; The screen arrangement per line:
; 20 bytes|20 bytes|20 bytes == 60 bytes.
;
; To make the screens look like the end of one screen isn't 
; directly attached to the start of the next, I insert
; one empty byte between each:
; 20 bytes|1 byte|20 bytes|1 byte|20 bytes == 62 bytes.
;
; So, the program can just use the first 62 bytes of each row, and
; ignore the last two, right? Not so. The program must offset its 
; base reference for the three screens due to the way the Atari 
; does horizontal scrolling. 
;
; When horizontal scrolling is enabled ANTIC reads more data beginning
; at the current memory scan address than it needs to display the
; visible graphics line -- it reads enough additional data to 
; maintain a buffer of 16 color clocks at the beginning of the 
; display line.
;
; Examples below assume a graphics mode that displays 8 color clocks 
; (pixels) per byte (the mode used for the game playfield.):
;
; Normal memory read and display:
; (Simple and obvious -- 20 bytes read. 20 bytes displayed) 
; P is displayed pixels from a byte
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3 ...|byte 18 |byte 19 |
; |PPPPPPPP|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|
; 
; Memory read and display for Horizontal scrolling:
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|
;   FEDCBA9|87654321|0 = HSCROL positions
;                    ^ HSCROL = 0
;
; Horizontal scrolling works by using the HSCROL register to specify
; how many of the 16 buffered color clocks at the start of the line 
; should be output for display.  The example above shows none of the 
; buffered pixels output, so the HSCROL value is 0. Note that in this 
; case of HSCROL value 0 the buffer causes the actual display output to 
; begin two bytes later in memory than specified by ANTIC's memory scan 
; pointer.  

; The HSCROL value may range from 0 buffered color clocks output to 
; display up to 15 buffered color clocks output.  The example below 
; shows HSCROL set to 3.
;
; Memory read and display for Horizontal scrolling when HSCROL = 3
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BBBBBBBB|BBBBBDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPNNN|
;   FEDCBA9|87654321|0 = HSCROL positions
;                ^ HSCROL = 3
;
; The number of color clocks output for display is still consistent with the 
; normal output for the mode of graphics.   The contents of the line 
; shifts to the right "losing" 3 color clocks at the right side of the screen
; while HSCROL adds 3 color clocks to the left side of the display.
;
; Note that while ANTIC buffers 16 color clocks of data, the HSCROL value can 
; only range up to 15.  This means the first buffered color clock is not
; displayable...
;
; Memory read and display for Horizontal scrolling when HSCROL = 15 ($F)
; (Not so obvious -- more than 20 bytes read. 20 bytes displayed.)
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is previously displayable pixels removed from display due to HSCROL shifting the pixels.
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |
; |BDDDDDDD|DDDDDDDD|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PNNNNNNN|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; | ^ HSCROL = 15 ($F)
;  
; Displaying that final color clock requires (at least) one more byte prior 
; to this byte allowing HSCROL to output the contents of this byte.
; In other words, begin displaying from a previous memory location 
; (the original byte 0 address - 2 bytes) and then set fine scroll HSCROL 
; value to 0.
;
; An interesting part of Atari horizontal scrolling is that the 16 color 
; clocks buffered can exceed the distance of one byte's worth of color clocks.
; Therefore the increment (or decrement) for coarse scrolling is greater than 
; 1 byte. Some ANTIC modes have two bytes per 16 color clocks, some have 
; 4 bytes.  This has the interesting effect that the same display can be output 
; by different variations of memory scan starting address and HSCROL.
; For example, the display output is identical for the two settings below:
; 
; P is displayed pixels from a byte
; B is buffered pixels
; D is buffered pixels added to display.
; N is pixels not displayed on right.
; Z is pixels not read/not buffered/not displayed from the left 
; MS (memory scan pointer points to byte 0)
;  v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |BBBBBBBB|BBBBBBBB|PPPPPPPP|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 0
;
; MS (memory scan pointer points to byte 1)
;           v
; |byte 0  |byte 1  |byte 2  |byte 3  |byte 4 ...|byte 19 |byte 20 |byte 21 |byte 22 |
; |ZZZZZZZZ|BBBBBBBB|DDDDDDDD|PPPPPPPP|PPP... ...|PPPPPPPP|PPPPPPPP|PPPPPPPP|NNNNNNNN|
; |        | FEDCBA9|87654321|0 = HSCROL positions
; |                  ^ HSCROL = 8
;
; So, the consequence of this discussion and horizontal scrolling's treatment of the 
; first byte of the buffer means that the program can't consider the first byte 
; completely displayable and will ignore it as part of the intended display output.  
; However, the program must still accommodate that byte in order to scroll to the 
; byte that follows. 
;
; Therefore, the memory map for the display lines looks like this: 
; ignore byte 0,1|20 bytes|1 byte|20 bytes|1 byte|20 bytes == 63 bytes.
;             0,1|2.....21|.22...|23....42|.43...|44....63
;                 ^               ^               ^ 
; "^" identify first visible character on screen.
;
; ANTIC buffers the first two bytes, so the LMS origination position 
; for each of the three screens relative to the base of each line:
;
; Left Screen:   Memory Scan +0,  HSCROL = 0 (or Memory Scan +1,  HSCROL = 8)
; Center Screen: Memory Scan +21, HSCROL = 0 (or Memory Scan +22, HSCROL = 8)
; Right Screen:  Memory Scan +42, HSCROL = 0 (or Memory Scan +43, HSCROL = 8)
;
; Reference lookup for Display List LMS offset for screen postition:
; 0 = left
; 1 = center
; 2 = right
;
BRICK_SCREEN_LMS  
	.byte 0,21,42,0
	.byte 
;
; and reference HSCROL value to align the correct bytes...
;
; (This is no longer needed, because we know it is always 0.
;
; BRICK_SCREEN_HSCROL 
;	.byte 0,0,0
;
; Same thing from the opposite movement perspective...
;
BRICK_SCREEN_REVERSE_LMS  
	.byte 42,21,0
;
; (This is no longer needed, because we know it is always 0.
;
;BRICK_SCREEN_REVERSE_HSCROL 
;	.byte 0,0,0
;
; DISPLAY LIST: offset from DL_BRICK_BASE to the low byte of LMS addresses:
; DL_BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.
;
BRICK_LMS_OFFSETS 
	.byte 1,5,9,13,17,21,25,29
;
; DERP! Several days of debug-o-rama determined the plainly obvious fact that 
; offsets are not addresses.   Targets screen LMS locations must be specific 
; addreses, therefore there is a different value for each row for each screen.
;
; (However, by aligning all the screen memory rows to 64 byte increments 
; beginning at a page, the high byte for any given row is always the the same 
; for that specific row, so the high byte is not needed for these tables.
;
BRICK_SCREEN_LEFT_LMS_TARGET
    .byte <BRICK_LINE0
    .byte <BRICK_LINE1
    .byte <BRICK_LINE2
    .byte <BRICK_LINE3
    .byte <BRICK_LINE4
    .byte <BRICK_LINE5
    .byte <BRICK_LINE6
    .byte <BRICK_LINE7
;
BRICK_SCREEN_CENTER_LMS_TARGET
    .byte <[BRICK_LINE0+21]
    .byte <[BRICK_LINE1+21]
    .byte <[BRICK_LINE2+21]
    .byte <[BRICK_LINE3+21]
    .byte <[BRICK_LINE4+21]
    .byte <[BRICK_LINE5+21]
    .byte <[BRICK_LINE6+21]
    .byte <[BRICK_LINE7+21]
;
BRICK_SCREEN_RIGHT_LMS_TARGET
    .byte <[BRICK_LINE0+42]
    .byte <[BRICK_LINE1+42]
    .byte <[BRICK_LINE2+42]
    .byte <[BRICK_LINE3+42]
    .byte <[BRICK_LINE4+42]
    .byte <[BRICK_LINE5+42]
    .byte <[BRICK_LINE6+42]
    .byte <[BRICK_LINE7+42]
;
; MAIN code sets the TARGET configuration of each line of 
; the playfield.  
; The VBI takes these instructions and adjusts the display 
; values during each frame.  
; The Display List provides the coarse scroll position.  
; The DLI sets the fine scroll and the colors for each line.

;
; DLI: Current HSCROL/fine scrolling position.
;
BRICK_CURRENT_HSCROL 
	.byte 0,0,0,0,0,0,0,0
;
; VBI/MAIN: Target HSCROL/fine scrolling destination for moving display.
;
; (This is no longer needed, because we know it is always 0.
;
;BRICK_SCREEN_TARGET_HSCROL 
;	.byte 0,0,0,0,0,0,0,0
;
; Target LMS offset/coarse scroll to move the display. 
; One target per display line... line 0 to line 7.
; See BRICK_LMS_OFFSETS for actual locations of LMS.
;
BRICK_SCREEN_TARGET_LMS 
    .byte <[BRICK_LINE0+21]
    .byte <[BRICK_LINE1+21]
    .byte <[BRICK_LINE2+21]
    .byte <[BRICK_LINE3+21]
    .byte <[BRICK_LINE4+21]
    .byte <[BRICK_LINE5+21]
    .byte <[BRICK_LINE6+21]
    .byte <[BRICK_LINE7+21]
;
; Increment or decrement the movement direction? 
; -1=view Left/graphics right, +1=view Right/graphics left
;
BRICK_SCREEN_DIRECTION 
	.byte 0,0,0,0,0,0,0,0
;
; Table of patterns-in-a-can for direction....
;
TABLE_CANNED_BRICK_DIRECTIONS ; random(8) * 8
	.byte 1,1,1,1,1,1,1,1                 ; all view Right/graphics left
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF ; all view Left/graphics right 
	.byte 1,1,1,1,$FF,$FF,$FF,$FF         ; top go Right, Bottom go Left
	.byte $FF,$FF,$FF,$FF,1,1,1,1         ; top go Left, Bottom go Right
	.byte 1,1,$FF,$FF,1,1,$FF,$FF         ; 2 go right, 2 go left, etc.
	.byte $FF,$FF,1,1,$FF,$FF,1,1         ; 2 go left, 2 go right, etc.
	.byte 1,$FF,1,$FF,1,$FF,1,$FF         ; right, left, right, left...
	.byte $FF,1,$FF,1,$FF,1,$FF,1         ; left, right, left, right...
;
; Brick scroll speed (HSCROLs +/- per frame).
; Note, that row 8 MUST ALWAYS be the fastest/max speed
; to insure the bottom row of bricks are in place before 
; the ball returns to collide with the bricks.
;
BRICK_SCREEN_HSCROL_MOVE 
	.byte 4,4,4,4,4,4,4,4
;
; Table of patterns-in-a-can for scroll speed....
;
TABLE_CANNED_BRICK_SPEED ; random(4) * 8
	.byte 4,4,4,4,4,4,4,4 ; Block move fastest
	.byte 1,1,2,2,3,3,4,4 ; Top slowest, bottom fastest.
	.byte 1,2,3,4,1,2,3,4 ; Two, slow-to-fast gradients.
	.byte 4,3,2,1,1,2,3,4 ; Center slowest, outside fastest. 
;
; Frame count to delay start of scroll movement.
; Note, that row 8 MUST ALWAYS be 0 to insure the bottom 
; row of bricks are in place before the ball returns to 
; collide with the bricks.
;
BRICK_SCREEN_MOVE_DELAY 
	.byte 0,0,0,0,0,0,0,0
;
; Table of patterns-in-a-can for delaying start of scroll.
; Note that a custom delay is chosen ONLY when the scroll
; DIRECTION is 1 or 0,  and the SPEED 0.
;
TABLE_CANNED_BRICKS_DELAY
	.byte 0,0,0,0,0,0,0,0         ; No Delay.
	.byte 30,30,20,20,10,10,0,0   ; 1/2 second gradient pairs
	.byte 60,60,40,40,20,20,0,0   ; 1 second gradient pairs
	.byte 120,120,80,80,40,40,0,0 ; 2 second gradient pairs 
	.byte 14,12,10,8,6,4,2,0      ; two frames each
	.byte 56,48,40,32,24,16,8,0   ; 8 frames each
	.byte 0,10,20,30,30,20,10,0   ; 1/2 second top/bottom gradient
	.byte 40,20,30,70,120,20,60,0 ; 2 second randomish 

;
; DLI: Set line colors....  introducing a little more variety than 
; the original game and elsewhere on the screen.
;
BRICK_CURRENT_COLOR ; Base color for brick gradients
	.ds 8 ; 8 bytes, one for each row.       

TABLE_COLOR_TITLE ; Colors for title screen.  R a i n b o w
	.byte COLOR_ORANGE1+2
	.byte COLOR_RED_ORANGE+2
	.byte COLOR_PURPLE+2
	.byte COLOR_BLUE1+2
	.byte COLOR_LITE_BLUE+2
	.byte COLOR_BLUE_GREEN+2
	.byte COLOR_YELLOW_GREEN+2
	.byte COLOR_LITE_ORANGE+2

TABLE_COLOR_BRICKS ; Colors for normal game bricks.
	.byte COLOR_PINK+2        ; "Red"
	.byte COLOR_PINK+2        ; "Red"
	.byte COLOR_RED_ORANGE+2  ; "Orange"
	.byte COLOR_RED_ORANGE+2  ; "Orange"
	.byte COLOR_GREEN+2       ; "Green"
	.byte COLOR_GREEN+2       ; "Green"
	.byte COLOR_LITE_ORANGE+2 ; "Yellow"
	.byte COLOR_LITE_ORANGE+2 ; "Yellow"

TABLE_COLOR_GAME_OVER ; Colors for Game Over Text.
	.byte COLOR_ORANGE1+2  ; 
	.byte COLOR_ORANGE1+2  ; 
	.byte COLOR_ORANGE2+2  ; 
	.byte COLOR_ORANGE2+2  ; 
	.byte COLOR_RED_ORANGE+2  ; "Orange"
	.byte COLOR_RED_ORANGE+2  ; "Orange"
	.byte COLOR_PINK+2        ; "Red"
	.byte COLOR_PINK+2        ; "Red"


;
; MAIN flag to VBI requesting start of screen transition.
;
BRICK_SCREEN_START_SCROLL = PARAM_35
; .byte 0
;
; MAIN signal to move immediately to target positions if value is 1.
; Copy the BRICK_BRICK_SCREEN_TARGET_LMS_LMS and 
; BRICK_SCREEN_TARGET_HSCROL to all current positions.
;
BRICK_SCREEN_IMMEDIATE_POSITION = PARAM_36
; .byte 0
;
; VBI Feedback to MAIN that it is busy moving
;
BRICK_SCREEN_IN_MOTION = PARAM_37
; .byte 0
;
; Table of starting addresses for each line. 
;
BRICK_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte <[BRICK_LINE0+[entry*64]]
	entry .= entry+1 ; next entry in table.
	.endr
	
BRICK_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 lines
	.byte >[BRICK_LINE0+[entry*64]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Base location of visible bricks (in the middle of the line)
;
BRICK_CENTER_SCREEN_TABLE_LO
	.byte <[BRICK_LINE0+23]
	.byte <[BRICK_LINE1+23]
	.byte <[BRICK_LINE2+23]
	.byte <[BRICK_LINE3+23]
	.byte <[BRICK_LINE4+23]
	.byte <[BRICK_LINE5+23]
	.byte <[BRICK_LINE6+23]
	.byte <[BRICK_LINE7+23]
	

	
BRICK_CENTER_SCREEN_TABLE_HI
	.byte >[BRICK_LINE0+23]
	.byte >[BRICK_LINE1+23]
	.byte >[BRICK_LINE2+23]
	.byte >[BRICK_LINE3+23]
	.byte >[BRICK_LINE4+23]
	.byte >[BRICK_LINE5+23]
	.byte >[BRICK_LINE6+23]
	.byte >[BRICK_LINE7+23]
	
;
; Mask to erase an individual brick, numbered 0 to 13.
; Starting byte offset for visible screen memory, then the AND mask 
; for 3 bytes because some bricks cross three bytes.
;
; This could have been done with four separate tables
; providing base offset, byte 0, byte 1, and byte 2.
; That would save multiplying brick number by 4.
; oh, well...
;
BRICK_MASK_TABLE
	.byte $00, ~00000000, ~00000011, ~11111111
	.byte $01, ~11111000, ~00000000, ~01111111
	.byte $03, ~00000000, ~00001111, ~11111111
	.byte $04, ~11100000, ~00000001, ~11111111

	.byte $05, ~11111100, ~00000000, ~00111111
	.byte $07, ~10000000, ~00000111, ~11111111
	.byte $08, ~11110000, ~00000000, ~11111111
	.byte $0a, ~00000000, ~00011111, ~11111111

	.byte $0b, ~11000000, ~00000011, ~11111111
	.byte $0c, ~11111000, ~00000000, ~01111111
	.byte $0e, ~00000000, ~00001111, ~11111111
	.byte $0f, ~11100000, ~00000001, ~11111111

	.byte $10, ~11111100, ~00000000, ~00111111
	.byte $12, ~10000000, ~00000000, ~00000000  ; This would also clear byte 21
;
; Test an individual brick, numbered 0 to 13.
; Starting byte offset for visible screen memory, then the AND mask 
; for 3 bytes because some bricks cross three bytes.
; If anything reports as 1 then a pric is present.
; (Almost the same as BRICK_MASK_TABLE EOR $FF)
;
BRICK_TEST_TABLE
	.byte $00, ~00011111, ~11111000, ~00000000
	.byte $01, ~00000011, ~11111111, ~00000000
	.byte $03, ~01111111, ~11100000, ~00000000
	.byte $04, ~00001111, ~11111100, ~00000000

	.byte $05, ~00000001, ~11111111, ~10000000
	.byte $07, ~00111111, ~11110000, ~00000000
	.byte $08, ~00000111, ~11111110, ~00000000
	.byte $0a, ~11111111, ~11000000, ~00000000

	.byte $0b, ~00011111, ~11111000, ~00000000
	.byte $0c, ~00000011, ~11111111, ~00000000
	.byte $0e, ~01111111, ~11100000, ~00000000
	.byte $0f, ~00001111, ~11111100, ~00000000

	.byte $10, ~00000001, ~11111111, ~10000000
	.byte $12, ~00111111, ~11110000, ~00000000


;
; Table for P/M Xpos of each brick left edge
;
BRICK_XPOS_LEFT_TABLE
	entry .= 0
	.rept 14 ; repeat for 14 bricks in a line
	.byte [MIN_PIXEL_X+[entry*BRICK_WIDTH]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Table for P/M Xpos of each brick right edge
;
BRICK_XPOS_RIGHT_TABLE
	entry .= 0
	.rept 14 ; repeat for 14 bricks in a line
	.byte [PLAYFIELD_LEFT_EDGE_NORMAL+BRICK_RIGHT_OFFSET+[entry*BRICK_WIDTH]]
	entry .= entry+1 ; next entry in table.
	.endr


; The "PLAYFIELD edge offset" for Y direction defined in the  
; custom chip include files is not used here, because the vertical 
; display is entirely managed by a custom display list instead of 
; the default Operating System graphics modes.
;
; Table for P/M Ypos of each brick top edge
;
BRICK_YPOS_TOP_TABLE
	entry .= BRICK_TOP_OFFSET
	.rept 8 ; repeat for 8 lines of bricks 
	.byte entry ; [BRICK_TOP_OFFSET+[entry*BRICK_HEIGHT]]
	entry .= entry+BRICK_HEIGHT ; next entry in table.
	.endr
;
; Table for P/M Ypos of each brick bottom edge
;
BRICK_YPOS_BOTTOM_TABLE
	entry .= BRICK_TOP_END_OFFSET
	.rept 8 ; repeat for 8 lines of bricks 
	.byte entry ; [BRICK_TOP_END_OFFSET+[entry*BRICK_HEIGHT]]
	entry .= entry+BRICK_HEIGHT ; next entry in table.
	.endr


; DL_BRICK_BASE+1, +5, +9, +13, +17, +21, +25, +29 is low byte of row.

;BRICK_LINE_MASTER
;	.byte ~00011111, ~11111011, ~11111111, ~01111111, ~11101111 ; 0, 1, 2, 3
;	.byte ~11111101, ~11111111, ~10111111, ~11110111, ~11111110 ; 3, 4, 5, 6
;	.byte ~11111111, ~11011111, ~11111011, ~11111111, ~01111111 ; 7, 8, 9, 10
;	.byte ~11101111, ~11111101, ~11111111, ~10111111, ~11110000 ; 10, 11, 12, 13


; Convert X coordinate to brick, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14.
; (The code receiving these values will likely decrement it into 0 - 13.)
; The Table does NOT contain entries for the entire playfield width.  It contains
; only the entries of the valid playfield from left bumper to right bumper.
; Three color clocks on the left and four on the right are not included in the 
; playfield.  
; (or from Normal Border Left Offset +3  to Normal Border Right Offset -4).
;
; The 11-ness of the brick width is what makes calculations a bear.  And this would
; have to be repeated for every pixel test for multiple position tests per each frame. 
; A lookup table reduces this computation to an indexed read.  
;
; Still this table is a highly wasteful 153 byte travesty. 

BALL_XPOS_TO_BRICK_TABLE
	.byte 1,1,1,1,1,1,1,1,1,1,0
	.byte 2,2,2,2,2,2,2,2,2,2,0
	.byte 3,3,3,3,3,3,3,3,3,3,0
	.byte 4,4,4,4,4,4,4,4,4,4,0
	.byte 5,5,5,5,5,5,5,5,5,5,0
	.byte 6,6,6,6,6,6,6,6,6,6,0
	.byte 7,7,7,7,7,7,7,7,7,7,0
	.byte 8,8,8,8,8,8,8,8,8,8,0
	.byte 9,9,9,9,9,9,9,9,9,9,0
	.byte 10,10,10,10,10,10,10,10,10,10,0
	.byte 11,11,11,11,11,11,11,11,11,11,0
	.byte 12,12,12,12,12,12,12,12,12,12,0
	.byte 13,13,13,13,13,13,13,13,13,13,0
	.byte 14,14,14,14,14,14,14,14,14,14

; Brick rows are 5 lines + 2 blanks between.  Another bad computation like
; the X Position deal.  
; (The code receiving these values will likely decrement it into 0 - 7.)
; When the Ball Y position to test is between the 
; first scan line and last scan line of the brick rows this lookup table
; identifies the row 1, 2, 3, 4, 5, 6, 7, 8.

BALL_YPOS_TO_BRICK_TABLE
	.byte 1,1,1,1,1,0,0
	.byte 2,2,2,2,2,0,0
	.byte 3,3,3,3,3,0,0
	.byte 4,4,4,4,4,0,0
	.byte 5,5,5,5,5,0,0
	.byte 6,6,6,6,6,0,0
	.byte 7,7,7,7,7,0,0
	.byte 8,8,8,8,8


; Other "BRICKS" things...
;
; Pointers to data to draw the Title screen logo
;
LOGO_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte <[LOGO_LINE0+[entry*19]]
	entry .= entry+1 ; next entry in table.
	.endr
	
LOGO_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte >[LOGO_LINE0+[entry*19]]
	entry .= entry+1 ; next entry in table.
	.endr
;
; Pointers to data to draw the Game Over screen
;
GAMEOVER_LINE_TABLE_LO
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte <[GAMEOVER_LINE0+[entry*16]]
	entry .= entry+1 ; next entry in table.
	.endr

GAMEOVER_LINE_TABLE_HI
	entry .= 0
	.rept 8 ; repeat for 8 rows
	.byte >[GAMEOVER_LINE0+[entry*16]]
	entry .= entry+1 ; next entry in table.
	.endr


	
	
	
	
	
	
;===============================================================================
; BOOM-O-MATIC.
;===============================================================================
; Players 0 and 1 implement a Boom animation for bricks knocked out.
; The animation overlays the destroyed brick with a player two scan lines 
; and two color clocks larger than the brick.  This is centered on the brick
; providing a first frame impression that the brick expands. On subsequent 
; frames the image shrinks and color fades. 
;
; A DLI cuts these two players HPOS for each line of bricks, so there are 
; two separate Boom-o-matics possible for each line.   Realistically, 
; given the ball motion and collision policy it is impossible to request 
; two Boom cycles begin on the same frame for the same row, and would be 
; unlikely to have multiple animations running on every line. (But, just
; in case the code plans for the worst.)
;
; When MAIN code detects collision it will generate a request for a Boom-O-Matic
; animation that VBI will service.  VBI will determine if the request is for
; Boom 1 or Boom 2 .  If both animation cycles are in progress the one with the
; most progress will reset itself for the new animation.
;
; Side note -- maybe a future iteration will utilize the boom-o-matic blocks 
; during Title or Game Over sequences.

ENABLE_BOOM = PARAM_38
; .byte 0

BOOM_REQUEST 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides flag to add this brick. 0 = no brick. 1 = new brick.

BOOM_REQUEST_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; MAIN provides brick number in this row. 0 - 13


BOOM_1_CYCLE 
	.byte 0,0,0,0,0,0,0,0 ; VBI needs one for each row (0 = no animation)
BOOM_2_CYCLE 
	.byte 0,0,0,0,0,0,0,0 ; VBI needs one for each row

BOOM_1_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; VBI uses Brick number on the row doing the Boom Cycle.
BOOM_2_BRICK 
	.byte 0,0,0,0,0,0,0,0 ; VBI uses Brick number on the row doing the Boom Cycle.

BOOM_1_HPOS 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs HPOS1 for row
BOOM_2_HPOS 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs HPOS2 for row

BOOM_1_SIZE 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M SIZE1 for row
BOOM_2_SIZE 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M SIZE2 for row

BOOM_1_COLPM 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M COLPM1 for row
BOOM_2_COLPM 
	.byte 0,0,0,0,0,0,0,0 ; DLI needs P/M COLPM2 for row

BOOM_CYCLE_HPOS ; by cycle frame -- relative to Brick from BRICK_XPOS_LEFT_TABLE
	.byte $ff,$ff,$00,$00,$01,$02,$03,$04,$04

BOOM_CYCLE_SIZE ; by cycle frame
	.byte PM_SIZE_DOUBLE ; 6 bits * 2 color clocks == 12 color clocks. ; 1
	.byte PM_SIZE_DOUBLE ; 6 bits * 2 color clocks == 12 color clocks. ; 2
	.byte PM_SIZE_DOUBLE ; 5 bits * 2 color clocks == 10 color clocks. ; 3
	.byte PM_SIZE_DOUBLE ; 5 bits * 2 color clocks == 10 color clocks. ; 4
	.byte PM_SIZE_NORMAL ; 8 bits * 1 color clocks == 8 color clocks.  ; 5
	.byte PM_SIZE_NORMAL ; 6 bits * 1 color clocks == 6 color clocks.  ; 6
	.byte PM_SIZE_NORMAL ; 4 bits * 1 color clocks == 4 color clocks.  ; 7
	.byte PM_SIZE_NORMAL ; 2 bits * 1 color clocks == 2 color clocks.  ; 8
	.byte PM_SIZE_NORMAL ; 2 bits * 1 color clocks == 2 color clocks.  ; 9

; Row Lookups based on cycle need to multiply by the number 
; of cycle frames.  Here is a general table of multiplying 
; times nine where the result fits into a byte (from 0 to 28)
;
TIMES_NINE
	.byte $00,9,18,27,36,45,54,63,72,81,90,
	.byte 99,108,117,126,135,144,153,162,171,180
	.byte 189,198,207,216,225,234,243,252

; We could change boom block color cycles.   
; Possibly use different color sets for running
; boom blocks as an animation addition when 
; transitioning on the initial game entry, or 
; prior to serving a new ball.
;	
BOOM_CYCLE_COLOR ; by row by cycle frame -- 9 frames per boom animation
	.byte $0E,COLOR_LITE_ORANGE|$0E,         COLOR_PINK|$0C,         COLOR_PINK|$0A,         COLOR_PINK|$08,         COLOR_PINK|$06,         COLOR_PINK|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,         COLOR_PINK|$0C,         COLOR_PINK|$0A,         COLOR_PINK|$08,         COLOR_PINK|$06,         COLOR_PINK|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,   COLOR_RED_ORANGE|$0C,   COLOR_RED_ORANGE|$0A,   COLOR_RED_ORANGE|$08,   COLOR_RED_ORANGE|$06,   COLOR_RED_ORANGE|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,   COLOR_RED_ORANGE|$0C,   COLOR_RED_ORANGE|$0A,   COLOR_RED_ORANGE|$08,   COLOR_RED_ORANGE|$06,   COLOR_RED_ORANGE|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,        COLOR_GREEN|$0C,        COLOR_GREEN|$0A,        COLOR_GREEN|$08,        COLOR_GREEN|$06,        COLOR_GREEN|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,        COLOR_GREEN|$0C,        COLOR_GREEN|$0A,        COLOR_GREEN|$08,        COLOR_GREEN|$06,        COLOR_GREEN|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,  COLOR_LITE_ORANGE|$0C,  COLOR_LITE_ORANGE|$0A,  COLOR_LITE_ORANGE|$08,  COLOR_LITE_ORANGE|$06,  COLOR_LITE_ORANGE|$04, $02,$00
	.byte $0E,COLOR_LITE_ORANGE|$0E,  COLOR_LITE_ORANGE|$0C,  COLOR_LITE_ORANGE|$0A,  COLOR_LITE_ORANGE|$08,  COLOR_LITE_ORANGE|$06,  COLOR_LITE_ORANGE|$04, $02,$00

; 7 bytes of Player image data per each cycle frame.
; The 8th and 9th byte 0 padded, since we are putting 
; Times Nine offset table to dual use.
;  	
BOOM_ANIMATION_FRAMES 
	.byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$00,$00 ; 7 scan lines, 6 bits * 2 color clocks == 12 color clocks. ; 1
	.byte $FC,$FC,$FC,$FC,$FC,$FC,$FC,$00,$00 ; 7 scan lines, 6 bits * 2 color clocks == 12 color clocks. ; 2
	.byte $00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00 ; 5 scan lines, 5 bits * 2 color clocks == 10 color clocks. ; 3
	.byte $00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00 ; 5 scan lines, 5 bits * 2 color clocks == 10 color clocks. ; 4
	.byte $00,$00,$FF,$FF,$FF,$00,$00,$00,$00 ; 3 scan lines, 8 bits * 1 color clocks == 8 color clocks.  ; 5
	.byte $00,$00,$FC,$FC,$FC,$00,$00,$00,$00 ; 3 scan lines, 6 bits * 1 color clocks == 6 color clocks.  ; 6
	.byte $00,$00,$00,$F0,$00,$00,$00,$00,$00 ; 1 scan line, 4 bits * 1 color clocks == 4 color clocks.   ; 7
	.byte $00,$00,$00,$C0,$00,$00,$00,$00,$00 ; 1 scan line, 2 bits * 1 color clocks == 2 color clocks.   ; 8
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00 ; 0 scan line, 0 bits * 0 color clocks == 0 color clocks.   ; 9

	
	
	
	
	
	
	
	
	
	
	
	
	



;===============================================================================
;	GAME INTERRUPT INCLUDES
;===============================================================================

;	.include "vbi.asm"
;===============================================================================
; **  **  *****   ****** 
; **  **  **  **    **   
; **  **  *****     **   
; **  **  **  **    **   
;  ****   **  **    **   
;   **    *****   ******  
;===============================================================================

;
; Insert the game's routine in the Deferred Vertical Blank Interrupt.
;
Set_VBI
	ldy #<Breakout_VBI ; LSB for routine
	ldx #>Breakout_VBI ; MSB for routine

	lda #7             ; Set Interrupt Vector 7 for Deferred VBI

	jsr SETVBV         ; and away we go.

	rts

;	
; Remove the game's Deferred Vertical Blank Interrupt.
;
Remove_VBI
	ldy #<XITVBV ; LSB of JMP to end deferred VBI
	ldx #>XITVBV ; MSB of JMP to end deferred VBI

	lda #7       ; Set Interrupt Vector 7 for Deferred Vertical Blank Interrupt.

	jsr SETVBV  ; and away we go.

	rts


.local
;
; MAIN directs things to happen. The magic of that happening is 
; (decided) here.  That is, much of the game guts, animation, and 
; timing either occurs here or is established here.  For the most 
; part, DLIs are only transferring values to registers per the
; directions determined here. 
;
Breakout_VBI

	; Set initial display values to be certain everything begins 
	; at a known state with the title.

;	lda TITLE_HPOSP0    ; set horizontal position for Player as Title character
;	sta HPOSP0
	
;	lda #PM_SIZE_NORMAL ; set size for Player as Title character 
;	sta SIZEP0

	lda #4     ; Horizontal fine scrolling. 
	sta HSCROL ; Title textline is shifted by HSCROLL to center it.
	
	; Force the initial DLI just in case one goes crazy and the 
	; DLI chaining gets messed up. 
	; This may be commented out when code is more final.
	
	lda #<DISPLAY_LIST_INTERRUPT ; DLI Vector
	sta VDSLST
	lda #>DISPLAY_LIST_INTERRUPT
	sta VDSLST+1


; ==============================================================
; MAINTAIN SUB-60 FPS TICKERS
; ==============================================================
	;
	; 30 FPS...  tick off 0, 1, 0, 1, 0, 1...
	;
	inc V_30FPS_TICKER
	lda V_30FPS_TICKER
	and #~00000001
	sta V_30FPS_TICKER
	;
	; 20 FPS... tick 2, 1, 0, 2, 1, 0... a bit differently  
	;
	lda V_20FPS_TICKER
	bne Skip_20FPS_Reset
	lda #~00000100 ; #4  which becomes 2 in this iteration, then 1, then 0
Skip_20FPS_Reset
	lsr A 
	sta V_20FPS_TICKER
	;
	; 15 FPS... tick off 0, 1, 2, 3, 0, 1, 2, 3...
	;
	inc V_15FPS_TICKER
	lda V_15FPS_TICKER
	and #~00000011
	sta V_15FPS_TICKER

	
; ==============================================================
; TITLE FLY IN
; ==============================================================

; End of Title section.
End_Title 

; whatever was decided for scrolling and flying text, 
; commit it to hardware for the title at the top of 
; the screen, so the first DLI does not have to do it.
	lda #0
;	lda TITLE_VSCROLL
	sta VSCROL
	
;	lda TITLE_HPOSP0
;	sta HPOSP0



	
	
; ==============================================================
; BALL:
; ==============================================================


End_Ball_Update	


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

;	lda DIAG_SLOW_ME_CLOCK
;	beq ?Continue_Thumper
;	dec DIAG_SLOW_ME_CLOCK
;	jmp Exit_VBI

;?Continue_Thumper
;	lda #$0D
;	sta DIAG_SLOW_ME_CLOCK
	
	
	

	
Thumper_Animator_VBI
; X is the Thumper type:
; 0 = horizontal, 
; 1 = left, 
; 2 = right
;
; Y is the current animation frame (if an animation 
; is in progress.)


End_Thumper_Bumper_VBI	
	
	
	

	
; ==============================================================
; BRICKS
; ==============================================================
; "Bricks" refers to the playfield bricks and 
; the graphics for the Title log and the Game
; Over screen.  "Bricks" may also be an empty
; line to remove/transition these objects between
; the different displays.
;
; The Bricks may be in a static state for maintaining 
; current contents, or in a transition state 
; moving another screen contents on to the display.
;
; The MAIN code preps the BRICK lines for movement,
; sets the direction of each, and then notifies the 
; VBI to make the updates.
;
; The VBI cares not about the game mode.  It only 
; cares whether or not the bricks lines should be 
; in motion and what direction to move them.
;
; Motion speed is a tricky thing. When moving a new
; set of game playfield bricks they must be in place 
; before the ball can travel down from the bottom 
; border of the bricks, to the paddle and back up to 
; the bottom row of bricks. 

; At current specs: 
; bottom of bricks = line 133 + 1 line = 134 
; Paddle = scan line 205 - 1 line = 204
; That is a distance of 70 lines travelled twice,
; a total of 140 scan lines.

; Taking into account worse case motion rounding when
; the ball hits the paddle that's potentially three
; less scan lines, or an actual 137 lines traveled. 
; At its fastest, the ball travels 3 scan lines per
; frame.
; 137 scan lines / 3 lines per frame means the new
; playfield must be moved into place in 45 frames
; or less.

; The scroll width of a full screen is 168 color 
; clocks. (160 for visible screen plus one byte 
; of pixels additional for spacing between screens).
; 168 color clocks / 45 frames is 3.7 color clocks
; per frame. 
; Therefore, rounding up to 4 color clocks per frame,
; the screen can transition in 42 frames, leaving 
; a few frames for safety.  

; Note that only the lowest line of bricks must be 
; in place at this time, so the ball can hit the 
; row. The other higher lines can begin moving later, 
; or move slower lending a more fluid look to 
; the transition.
; 
; The Title Logo and the Game Over graphics can 
; transition at any speed possible, since the ball
; is not dependant (or even visible) when these 
; graphics are on screen.
; 
; Scrolling to the left screen needs a special case, 
; because the final stopping location is outside the 
; 0 - 7 color clock positions used for scrolling.
; (and using 0-15 would make this even more weird.)
; 
; Reminders: 
; -1 == Move view left/screen bricks Right = Increment HSCROL, Decrement LMS.
; +1 == Move view right/screen bricks Left = Decrement HSCROL, Increment LMS
;
; Two different screen moves here.  
;
; The first is an immediate move to the declared positions.  This would 
; be used to reset to starting positions before setting up a scroll.
;
; The second scroll is fine scroll from current position to target position.

; ***********************************************************
; Usually, I use X for looping, and Y as optional index
; to something, because only Y allows (ZPAGE),Y addressing.
; But, I need to update/increment the LMS address in a 
; Display list based on an offset and only X allows
; INC MEMORY,X.  Since there is no zero page indirection 
; here, Y is used for row counting and X is for DL offset.
;
	lda BRICK_SCREEN_IMMEDIATE_POSITION ; move screen directly.
	beq Fine_Scroll_Display             ; if not set, then try fine scroll

; ***************
; IMMEDIATE MOVE   
; ***************
	
	ldy #7

Do_Next_Immediate_Move
	ldx BRICK_LMS_OFFSETS,y          ; X = LMS low byte for current row in the Display List
	lda BRICK_SCREEN_TARGET_LMS,y    ; Get the LMS destination position.
	sta DL_BRICK_BASE,x              ; Set the new Display List LMS pointer.
	lda #0                           ; This is always 0, so no lookup needed.
	sta BRICK_CURRENT_HSCROL,y       ; Set the current Hscrol for this row.
	
	dey
	bpl Do_Next_Immediate_Move

	lda #0                           ; Clear the immediate move flag, and...
	sta BRICK_SCREEN_IMMEDIATE_POSITION
;	beq End_Brick_Scroll_Update
	jmp End_Brick_Scroll_Update      ; skip over doing fine scroll...

; *****************
; FINE SCROLL ENTRY   
; *****************

Fine_Scroll_Display   
	lda BRICK_SCREEN_START_SCROLL ; MAIN says to start scrolling?
	beq Check_Brick_Scroll        ; No?  So, is a Scroll already running?
	; If a scroll is already in progress when MAIN toggles the
	; BRICK_SCREEN_START_SCROLL flag it has no effect.
	; The current scroll keeps on scrolling.
	lda #0
	sta BRICK_SCREEN_START_SCROLL ; Turn off MAIN request.
	inc BRICK_SCREEN_IN_MOTION    ; Raise flag for Scroll in progress to trick next evaluation.

Check_Brick_Scroll
	lda BRICK_SCREEN_IN_MOTION    ; Is the screen in motion?
	bne Reset_Brick_In_Motion     ; Yes. Reset for this frame.
;	beq End_Brick_Scroll_Update
	jmp End_Brick_Scroll_Update   ; Nothing in motion.  Skip scrolling.

Reset_Brick_In_Motion
	lda #0                        ; Temporarily force indicator for no motion
	sta BRICK_SCREEN_IN_MOTION 

; ***************
; DELAY OR SCROLL   
; ***************
	
	ldy #7 ; start at last/bottom row.

Check_Pause_or_Movement
	lda BRICK_SCREEN_MOVE_DELAY,y ; Delay for frame count?
	beq Move_Brick_Row            ; No.  Is there fine scroll?

	inc BRICK_SCREEN_IN_MOTION    ; "Pause" still means things are in progress.	

	tya                           ; Copy Y to X, because this needs to use  
	tax                           ; DEC MEMORY,X, and X is being used for LMS offset.

	dec BRICK_SCREEN_MOVE_DELAY,x ; Decrement timer frame counter.
	jmp Do_Next_Brick_Row
	
Move_Brick_Row
	ldx BRICK_LMS_OFFSETS,y       ; X = LMS low byte for current row in the Display List

	lda DL_BRICK_BASE,x           ; What is the Display List LMS pointer now?	
	cmp BRICK_SCREEN_TARGET_LMS,y ; Does it match target?
	
	beq ?Finish_View_Right_HScroll ; Yes. Then maybe more HScroll needed?

; Reminders: 
; -1 == Move view left/screen bricks Right = Increment HSCROL, Decrement LMS.
; +1 == Move view right/screen bricks Left = Decrement HSCROL, Increment LMS.
	
	lda BRICK_SCREEN_DIRECTION,y ; Are we going left or right?
	bmi Do_View_Scroll_Left      ; -1 = view left/graphics right, +1 = view Right/graphics left

; *****************
; SCROLL VIEW RIGHT - Move View Right/screen bricks left 
; *****************

	lda BRICK_CURRENT_HSCROL,y      ; get the current Hscrol for this row.
	
	sec
	sbc BRICK_SCREEN_HSCROL_MOVE,y  ; decrement Hscrol to move graphics left.

; Remember that LMS+1, HSCROL 8 is the same result as LMS+0, HSCROL 0.
; Therefore, HSCROL cannot reach 8.  It must "wrap" after 7 to force coarse 
; scroll to make the motion fliud.

; Assuming HSCROL starts from 0 to 7 and the HSCROL adjustment may 
; be 1 to 8 color clocks, then the result may be HSCROL positions:
; 6, 5, 4, 3, 2, 1, 0, -1, -2, -3, -4, -5, -6, -7, -8
; where all negative values are positions in the next screen byte.
; Therefore, add 8 to the HSCROL to get to the correct position.

	bpl Update_HScrol       ; If still positive, then no coarse scroll.

	clc                     ; Add to return this...
	adc #8                  ; ... to positive. (using 8, not 16 color clocks)
	
	inc DL_BRICK_BASE,x     ; Increment LMS to Coarse scroll view right, graphics left
	jmp Update_HScrol       ; JMP - the inc above Should always be non-zero?

; Note that if the LMS increment above has now reached the target LMS 
; location the current (calculated) HSCROL in the Accumulator is valid,
; so no further evaluation is needed. The next frame(s) will go to the
; "Finish_View_Right_HScroll" section until everything matches exactly.	
	
; Reminders: 
; -1 == Move view left/screen bricks Right = Increment HSCROL, Decrement LMS.
; +1 == Move view right/screen bricks Left = Decrement HSCROL, Increment LMS

; ****************
; SCROLL VIEW LEFT - Move view left/screen bricks Right
; ****************

Do_View_Scroll_Left
	lda BRICK_CURRENT_HSCROL,y      ; get the current Hscrol for this row.
	
	clc
	adc BRICK_SCREEN_HSCROL_MOVE,y  ; increment Hscrol to move graphics right.

; Remember that LMS+1, HSCROL 8 is the same result as LMS+0, HSCROL 0.
; Therefore, HSCROL cannot reach 8.  It must "wrap" after 7 to force coarse 
; scroll to make the motion fliud.

; Assuming HSCROL starts from 0 to 7 and the HSCROL adjustment may 
; be 1 to 8 color clocks, then the result may be HSCROL positions:
; 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 
; where all values over 7 are positions in the next screen byte.
; Therefore, subtract 8 from the HSCROL to get to the correct position.
	
	cmp #8 ; is less than 8 ? 
	bcc Update_HScrol       ; No carry means Acc < 8, so no coarse scroll.???????????

	sec
	sbc #8                  ; Subtract 8 (because fine scrolling 8, not 16 color clocks)
	
	dec DL_BRICK_BASE,x     ; Decrement LMS to coarse scroll graphics right.
	
; Note that if the LMS decrement above has now reached the target LMS 
; location the current (calculated) HSCROL in the Accumulator may not
; be valid. At the target LMS location only HCROL value 0 is valid.
; Therefore, further evaluation is needed to truncate HSCROL. 

	pha ; Save current HSCROL for when we need it again.
	
	lda DL_BRICK_BASE,x           ; Get the current (new) LMS
	cmp BRICK_SCREEN_TARGET_LMS,y ; Compare to target
	beq ?End_Of_Right_Scroll      ; Matching LMS means truncate HSCROL to 0
	
	pla                           ; LMS does not match. Get the HSCROL back.
	jmp Update_HScrol             ; 0 to 7 is positive, Go update scroll

?End_Of_Right_Scroll
	pla                           ; Discard the saved HSCROL off the stack.
	jmp Do_Finish_HScroll         ; force to 0 and update new hscrol.

; *****************
; FINAL FINE SCROLL - Move View Right/screen bricks left 
; *****************
	
; We know the current LMS matches the target LMS. 
; If this is a View Right/Graphics Left move then more fine
; scrolling may be needed to reach the target. 

?Finish_View_Right_HScroll 
	lda BRICK_CURRENT_HSCROL,y ; If this is zero then HSCROL is done.
	beq Do_Next_Brick_Row      ; Everything matches. nothing to do.

	lda BRICK_SCREEN_DIRECTION,y ; -1 = view left/graphics right, +1 = view Right/graphics left 
	bmi Do_Finish_HScroll        ; If View Left/Graphics Right, then we're done.
	
; Scroll View Right/screen contents left 
	lda BRICK_CURRENT_HSCROL,y      ; get the current Hscrol for this row.
	
	sec 
	sbc BRICK_SCREEN_HSCROL_MOVE,y  ; decrement it to move graphics left.

	bpl Update_HScrol               ; If positive, then no forced (re)adjustment.

; The new HSCROL went negative, therefore the
; scroll is over.  Force HSCROL to 0 position.	
	
Do_Finish_HScroll
	lda #0 ; Force to 0, as this is the end of scrolling.                      

Update_HScrol
	and #$07                   ; There's a rumor I'm letting this reach 8 by accident
	sta BRICK_CURRENT_HSCROL,y ; Save new HSCROL.
	inc BRICK_SCREEN_IN_MOTION ; Indicate things in motion on this frame.
	
; ***************
; END LOOP  
; ***************

Do_Next_Brick_Row
	dey
	bmi End_Brick_Scroll_Update
;	bpl Check_Pause_or_Movement ; Do_Row_Movement
	jmp Check_Pause_or_Movement
	
End_Brick_Scroll_Update



;===============================================================================
; BOOM-O-MATIC
;===============================================================================
; Players 0 and 1 implement a Boom animation for bricks knocked out.
; The animation overlays the destroyed brick with a rectangle two scan 
; lines taller and and two color clocks wider than the brick.  This is 
; centered on the brick providing a first frame impression that the brick 
; expands. On subsequent frames the image shrinks and color fades. 
;
; A DLI cuts these two players' HPOS for each line of bricks, so there are 
; two separate Boom-o-matics possible for each line.   Realistically, 
; given the ball motion and collision policy it is impossible to request 
; two Boom cycles begin on the same frame for the same row, and would be 
; unlikely to have multiple animations running on every line. (But, just
; in case the code plans for the worst.)
;
; When MAIN code detects collision it will generate a request for a Boom-O-Matic
; animation that VBI will service.  VBI will determine if the request is for
; Boom 1 or Boom 2 .  If both animation cycles are in progress the one with the
; most progress will reset itself for the new animation.
;
; Side note -- maybe a future iteration will utilize the boom-o-matic blocks 
; during Title or Game Over sequences.
;===============================================================================

;
; First, is boom enabled?
;
	lda ENABLE_BOOM
	bne Add_New_Boom
	; No boom. MAIN should have zero'd all HPOS and animation states.
	; Like this....
	; Maybe MAIN should do this after dsabling the boom bricks.
	;
	ldx #7
	lda #0
Clear_Boom
	sta BOOM_1_HPOS,x
	sta BOOM_2_HPOS,x
	sta BOOM_1_CYCLE,x
	sta BOOM_2_CYCLE,x
	dex 
	bpl Clear_Boom
	
	jmp End_Boom_O_Matic

	; !!! NEW RULES FOR NEW BOOM !!!   
	; The code was accounting for impossible situations and was ballooning 
	; into something stupidly insane.  There are now limits on behavior.
	; It is still insanne, but mildly less stupid.
	;
	; Upon hitting a brick, the ball must next hit the paddle or 
	; the top wall before allowing collision with another brick.
	; Therefor, MAIN has no possible way it can request starting 
	; more than one boom cycle on the same row on the same frame.
	; Thus, MAIN will have only one request input to VBI. 
	; The VBI input handler will push down older requests to the 
	; second control block if needed. 
	;
	; MAIN now has only one request buffer for entering a brick into 
	; the Boom cycle animations.  If another animation is already 
	; running on that same row, it is pushed down into the second
	; list, and the new request goes into the first list.  Thus 
	; the "1" list entries will always be newer than the "2" lists', 
	; and if there is no animation running in the "1" list then 
	; the "2" list can be assumed to be unused/idle.

; ****************
; ADD NEW BOOMS - If a new request exists, add to animation list "1" 
; ****************
;
Add_New_Boom ; Add any new requests to the lists.
	ldx #7 

New_Boom_Loop
	lda BOOM_REQUEST,x ; is request flag set?
	beq Next_Boom_Test ; no, therefore 2 would not be set either.
	lda BOOM_1_CYCLE,x ; If this is 0 then use it.
	beq Assign_Boom_1
	; Boom 1 already in use.
	; First move Boom 1 animation states to Boom 2 list.
	jsr Push_Boom_1_To_Boom_2
	
	; Assign request 1 to Boom 1.
Assign_Boom_1
	lda BOOM_REQUEST_BRICK,x ; Get requested brick, 0 to 13
	sta BOOM_1_BRICK,x       ; assign to this row's animation slot
	lda #1                     
	sta BOOM_1_CYCLE,x       ; set first frame of animation
    lda #0
	sta BOOM_REQUEST,x       ; Turn off input request.
	
Next_Boom_Test
	dex
	bpl New_Boom_Loop

; Note that the 20fps clock applied here means new boom requests 
; could be added for three frames before any animation occurs.
;  
; (In a better world, this should be modified to apply the first 
; frame animation on the same frame when the request is made, and 
; and then apply 20fps updates to that afterwards.)
;	
; ****************
; BOOM TICKER - Reduce animation rate to 20 frames/sec
; ****************
;
Check_Boom_Ticker
	lda V_20FPS_TICKER
	beq Animate_Boom_O_Matic
	jmp End_Boom_O_Matic
	

; ****************
; ANIMATE BOOMS - Animate where cycle is non-zero. Incremement animation Cycle.
; ****************
;	
; Next walk through the current Boom cycles, do the 
; animation changes and update the values.
;
Animate_Boom_O_Matic
	ldx #7 

Boom_Animation_Loop
	stx V_TEMP_ROW       ; Save Row
	
	ldy BOOM_1_CYCLE,x   ; Y = Cycle. If this is not zero, 
	bne Boom_Animation_1 ; then animate it.
	; if cycle is 0 then it reached the last frame.  
	lda #0               ; Force HPOS 0, just in case.
	sta BOOM_1_HPOS,x
	sta BOOM_2_HPOS,x    ; 2 is older, so it must be idle, too.
	
	jmp Next_Boom_Animation


; ****************
; ANIMATE BOOM 1
; ****************
;
Boom_Animation_1
	dey                   ; makes cycle 1 - 9 easier to lookup as 0 - 8
	sty V_TEMP_CYCLE      ; Save Cycle. Y = Cycle.

	lda BOOM_CYCLE_SIZE,y ; Get P/M Horizontal Size for this cycle
	sta BOOM_1_SIZE,x     ; Set size.

	; P/M position varies by brick, and by cycle.
	;
	ldy BOOM_1_BRICK,x          ; Y = Brick number for row
	lda BRICK_XPOS_LEFT_TABLE,y ; get HPOS for brick. 
	ldy V_TEMP_CYCLE            ; Y = current cycle.
	clc
	adc BOOM_CYCLE_HPOS,y       ; adjust HPOS by the current animation state.
	sta BOOM_1_HPOS,x           ; Save HPOS 
	
	; P/M Color is based on row and by cycle.
	; Multiply row times 9 in offset table, then add cycle to get entry.
	;
	lda TIMES_NINE,x            ; A = Row * 9
	clc
	adc V_TEMP_CYCLE            ; A = A + Cycle
	tay                         ; Y = (row * 9) + cycle
	lda BOOM_CYCLE_COLOR,y      ; A = cycle_color[ (row * 9) + cycle ]
	sta BOOM_1_COLPM,x          ; Store new color for boom on this row.
	
	; Last: copy 7 bytes of P/M image data to correct Y pos.
	; Convert row to P/M ypos.
	; multiply cycle times 9.
	; copy 7 bytes from table to p/m base.
	;
	ldy BRICK_YPOS_TOP_TABLE,x ; Get scan line of top of row.
	dey                        ; -1.  one line higher for exploding brick.
	sty ZTEMP_PMADR            ; low byte for player/missile address. 
	lda #>PMADR_BASE0          ; Player 0 Base,  
	sta ZTEMP_PMADR+1          ; high byte.

	; Get this cycle's starting animation frame.	
	ldy V_TEMP_CYCLE           ; Y = Cycle again.
	lda TIMES_NINE,y           ; A = Cycle * 9

	tax                        ; X = cycle * 9                        
	ldy #$00

	; Copy the current cycle's animation 
	; image to the Player.
	;
Loop_Copy_PM_1_Boom
	lda BOOM_ANIMATION_FRAMES,x ; Read from animation table[ (cycle * 9) + x ]
	sta (ZTEMP_PMADR),y         ; Store in Player memory + Y
	inx                         ; increment to next byte in animation image
	iny                         ; increment to next byte of player memory
	cpy #7                      ; stop at 7 bytes.
	bne Loop_Copy_PM_1_Boom

	; Boom 1 is done.  
	; Increment the cycle
	;
	ldx V_TEMP_ROW  	        ; Get the real row back.
    ldy BOOM_1_CYCLE,x          ; Y = current cycle
    iny                         ; increment cycle
    cpy #10                     ; only 9 frames. 10 is the end.
    bne Finish_1_Cycle          ; If not the end, then update
    ldy #0                      ; If the end, then zero the cycle.
    
Finish_1_Cycle
	tya                         ; A = Y
    sta BOOM_1_CYCLE,x          ; Save new Cycle state.


Test_2_Boom
	ldy BOOM_2_CYCLE,x   ; If this is not zero, 
	bne Boom_Animation_2 ; then animate it.
	; if cycle is 0 then it reached the last frame. 
	lda #0               ; Force HPOS 0, just in case.
	sta BOOM_2_HPOS,x
	
	jmp Next_Boom_Animation

; ****************
; ANIMATE BOOM 2
; ****************
;
Boom_Animation_2
	dey                     ; makes cycle 1 - 9 easier to lookup as 0 - 8
	sty V_TEMP_CYCLE        ; Save Cycle for second boom
	
	lda BOOM_CYCLE_SIZE,y   ; Get P/M Horizontal Size for this cycle
	sta BOOM_2_SIZE,x       ; Set size.

	; P/M position varies by brick, and by cycle.
	;
	ldy BOOM_2_BRICK,x          ; Y = Brick number for row
	lda BRICK_XPOS_LEFT_TABLE,y ; get HPOS for brick. 
	ldy V_TEMP_CYCLE            ; Y = current cycle.
	clc
	adc BOOM_CYCLE_HPOS,y       ; adjust HPOS by the current animation state.
	sta BOOM_2_HPOS,x           ; Save HPOS 
	
	; P/M Color is based on row and by cycle.
	; Multiply row times 9 in offset table, then add cycle to get entry.
	;
	lda TIMES_NINE,x            ; A = Row * 9
	clc
	adc V_TEMP_CYCLE            ; A = A + Cycle
	tay                         ; Y = (row * 9) + cycle
	lda BOOM_CYCLE_COLOR,y      ; A = cycle_color[ (row * 9) + cycle ]
	sta BOOM_2_COLPM,x          ; Store new color for boom on this row.
	
	; Last: copy 7 bytes of P/M image data to correct Y pos.
	; Convert row to P/M ypos.
	; multiply cycle times 9.
	; copy 7 bytes from table to p/m base.
	;
	ldy BRICK_YPOS_TOP_TABLE,x ; Get scan line of top of row.
	dey                        ; -1.  one line higher for exploding brick.
	sty ZTEMP_PMADR            ; low byte for player/missile address. 
	lda #>PMADR_BASE1          ; Player 1 Base,  
	sta ZTEMP_PMADR+1          ; high byte.

	; Get this cycle's starting animation frame.	
	ldy V_TEMP_CYCLE           ; Y = Cycle again.
	lda TIMES_NINE,y           ; A = Cycle * 9

	tax                        ; X = cycle * 9                        
	ldy #$00

	; Copy the current cycle's animation 
	; image to the Player.
	;
Loop_Copy_PM_2_Boom
	lda BOOM_ANIMATION_FRAMES,x ; Read from animation table[ (cycle * 9) + x ]
	sta (ZTEMP_PMADR),y         ; Store in Player memory + Y
	inx                         ; increment to next byte in animation image
	iny                         ; increment to next byte of player memory
	cpy #7                      ; stop at 7 bytes.
	bne Loop_Copy_PM_2_Boom

	; Boom 2 is done.  
	; Increment the cycle
	;
	ldx V_TEMP_ROW  	        ; Get the real row back.
    ldy BOOM_2_CYCLE,x          ; Y = current cycle
    iny                         ; increment cycle
    cpy #10                     ; only 9 frames. 10 is the end.
    bne Finish_2_Cycle          ; If not the end, then update
    ldy #0                      ; If the end, then zero the cycle.
    
Finish_2_Cycle
	tya                         ; A = Y
    sta BOOM_2_CYCLE,x          ; Save new Cycle state.
	
	
; ****************
; END ROW LOOP
; ****************
;    
Next_Boom_Animation
	dex
	bmi End_Boom_O_Matic
;	bpl Boom_Animation_Loop
	jmp Boom_Animation_Loop

End_Boom_O_Matic



	
	
	
	

;===============================================================================
; THE END OF USER DEFERRED VBI ROUTINE 
;===============================================================================

Exit_VBI
; Finito.
	jmp XITVBV



	

;=============================================
; Push the current state of Boom 1 to Boom 2.
; X = current row.
Push_Boom_1_To_Boom_2
	lda BOOM_1_BRICK,x
	sta BOOM_2_BRICK,x
	lda BOOM_1_CYCLE,x
	sta BOOM_2_CYCLE,x

	rts


	
	
	
	

;	.include "dli.asm"
;===============================================================================
; ****    **      ******  
; ** **   **        **   
; **  **  **        **   
; **  **  **        **   
; ** **   **        **   
; ****    ******  ******  
;===============================================================================

DISPLAY_LIST_INTERRUPT




DLI_1 ; Save registers
	pha


End_DLI_1 ; End of routine.  Point to next routine.
	lda #<DLI_2
	sta VDSLST
	lda #>DLI_2
	sta VDSLST+1
	
	pla ; Restore registers for exit

	rti



DLI_2
	pha
	txa
	pha
	tya
	pha

	; GTIA Fifth Player/Missiles = COLPF3. Priority: PM0/1, Playfield, PM2/3
	lda #[FIFTH_PLAYER|2] 
	sta PRIOR
	sta HITCLR

	; Screen parameters...
	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NORMAL|PM_1LINE_RESOLUTION]
	STA WSYNC
	sta DMACTL

	
	
	

	
	
	
End_DLI_2 ; End of routine.  Point to next routine.
	lda #<DLI_3
	sta VDSLST
	lda #>DLI_3
	sta VDSLST+1

	pla
	tay
	pla
	tax
	pla

	rti


	
	
	
	
	
	
; DLI3: Hkernel 8 times....
;      Set HSCROLL for line, VSCROLL = 5, then Set COLPF0 for 5 lines.
;      Reset VScroll to 1 (allowing 2 blank lines.)
;      Set P/M Boom objects, HPOS, COLPM, SIZE
;      Repeat HKernel.
;
; Define 8 rows of Bricks.
; Each is 5 lines of mode C graphics, plus 2 blank line.
; The 5 rows of graphics are defined by using the VSCROL
; exploit to expand one line of mode C into five lines.
;
; This:
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL
;   .byte DL_BLANK_2
; Becomes this:
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   DL_MAP_C
;   Blank Line
;   Blank Line
;
; The Blank lines provide space for expansion of the boom blocks over the bricks.
; Therefore they must be positioned in the blank line before the brick line.
; (An extra blank scan line follows the line starting the DLI to allow for this
; space on the first line)
;
; So, here is the DLI line change order:
;   DL_BLANK_1|DL_DLI                      Set hpos, size, color for Boom 1 and Boom2 (1)
;   DL_BLANK_1                             Set Vscroll 11 and HSCROLL for Brick Line 1 - set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (1)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (2)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 2 - set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (2)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (3)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 3 - set color COLPF0
; etc. . . .
;   DL_BLANK_1                             Set hpos, size, color for Boom 1 and Boom2 (8)
;   DL_BLANK_1                             Set Vscroll and HSCROLL for Brick Line 8 - set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set color COLPF0 (8)
;   DL_MAP_C|DL_LMS|DL_VSCROLL|DL_HSCROLL  Set VScroll 0
;   DL_BLANK_1
;   DL_BLANK_1
;-------------------------------------------
; color 1 = bricks.
; Player 1 = Boom animation 1
; Player 2 = Boom animation 2
;-------------------------------------------
; per brick line
; COLPM1, COLPM2
; HPOSP1, HPOSP2
; SIZEP1, SIZEP2
; COLPF0, HSCROLL
;-------------------------------------------
DLI_3
	pha
	txa
	pha
	tya
	pha

	ldx #0  ; Starting at line 0 first line of bricks.

; DLI ENTRY IS AN EXTRA SCAN LINE ABOVE 
; WITH ONE BLANK LINE IN BETWEEN.

DLI3_DO_BOOM_AND_BRICKS

; Current position is 
; -2 == ENTRY line -- end of blank line AND
; 5 == LINE 1 of 2 BLANK for boom blocks which means we're at
; the ending line of a boom block for the prior brick row.

	; Set hscroll for the upcoming brick line.
	lda BRICK_CURRENT_HSCROL,x
	sta HSCROL
	
	; load up to set the next Boom animation postitions.
	lda BOOM_1_HPOS,x
	ldy BOOM_2_HPOS,x
	
	sta WSYNC ; drop to the top of the next boom block lines.

; -1 == 1 BLANK BEFORE 5 BLOCK
; 6 == LINE 2 of 2 BLANK

	; six store, four load after wsync.   Hope this fits. 
	; At least there's no graphics or character set DMA on this line.
	sta HPOSP0
	sty HPOSP1

	lda BOOM_1_SIZE,x
	sta SIZEP0
	lda BOOM_2_SIZE,x
	sta SIZEP1

	lda BOOM_1_COLPM,x
	sta COLPM0
	lda BOOM_2_COLPM,x
	sta COLPM1

	; Prep to apply color to the BRICK lines
	ldy BRICK_CURRENT_COLOR,x

	; Here we are triggering unnatural behavior in ANTIC.  Resetting
	; VSCROL to a value larger than the number of scan lines in this 
	; one-scan line graphics mode causes ANTIC to repeat the same line
	; of graphics data for several scan lines. This trick creates a 
	; 5 scan line tall brick that has the DMA LMS load of only one line. 
	; This allows convenient brick handling -- the main code only 
	; manipulates pixels for one graphics line line resulting in 
	; 5 lines of work. 

	; At the current position ANTIC is displying the second
	; blank line of a 2-blank line instruction (DL_BLANK_2 or $10)
	; VSCROL needs to be toggled to the number of scan lines in this 
	; instruction to stop ANTIC from adding more scan lines.
	
	lda #1 ; the blank instruction scan lines numbered 0, 1
	sta WSYNC
	
; 0 == LINE 1 of 5 BLOCK  (ANTIC MODE C, 1 scan line tall)

	sta VSCROL ; Reset to finish displaying the blank lines.
	; Next, trick Antic into extending the Mode C line.  
	; Setting 12 will display scan lines 12, 13, 14, 15, 0.
	lda #12  
	sta VSCROL

	sty COLPF0                ; scan line 12 (1)

	iny
	iny
	sty WSYNC
	
; 1 == LINE 2 of 5 BLOCK	
	
	sty COLPF0                ; scan line 13 (2)

	iny
	iny	
	sty WSYNC
	
; 2 == LINE 3 of 5 BLOCK	
		
	sty COLPF0                ; scan line 14 (3)

	iny
	iny
	sty WSYNC
	
; 3 == LINE 4 of 5 BLOCK	
	
	sty COLPF0                ; scan line 15 (4)

	iny
	iny
	sty WSYNC
	
; 4 == LINE 5 of 5 BLOCK	
	
	sty COLPF0                ; scan line 0 (5)

	; skip one blank scan line for the bottom edge of 
	; the current row of BOOM blocks.
	sta WSYNC    
		
; 5 == LINE 1 of 2 BLANK	

	inx                   ; next row of bricks
	cpx #8
	bne DLI3_DO_BOOM_AND_BRICKS

	; Have to continue the VSCROL abuse in order to leave the proper
	; two scan lines after the bricks.

; Current position is 
; 5 == LINE 1 of 2 BLANK for boom blocks which means we're at
; the ending line of a boom block for the prior brick row.
	
	sta WSYNC ; drop to the top of the next boom block lines.

; 6 == LINE 2 of 2 BLANK
	
	lda #1 ; the blank instruction scan lines numbered 0, 1
	sta WSYNC
	
; - DONE

	sta VSCROL ; Reset to finish displaying the blank lines.



End_DLI_3 ; End of routine.  Point to next routine.
	lda #<DLI_4
	sta VDSLST
	lda #>DLI_4
	sta VDSLST+1


	lda #$0
	sta WSYNC
	sta COLBK
	
	
	pla
	tay
	pla
	tax
	pla

	rti


	
	
	
	
	
		
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

DLI_4
	pha

	lda #0
	ldy #$E0
	sty WSYNC
	sty CHBASE
	sta COLPF1
	sta VSCROL
	lda #$0A
	sta COLPF2
	
	
;===============================================================================
; ****    **      ******  
; ** **   **        **   
; **  **  **        **   
; **  **  **        **   
; ** **   **        **   
; ****    ******  ******  
;===============================================================================

End_DLI_4 ; End of routine.  Point to next routine.
	lda #<DLI_1
	sta VDSLST
	lda #>DLI_1
	sta VDSLST+1

	pla

	rti


	
	


	

;===============================================================================
;  ****   ****  *****  ****** ****** **  **
; **     **  ** **  ** **     **     *** ** 
;  ****  **     **  ** *****  *****  ****** 
;     ** **     *****  **     **     ****** 
;     ** **  ** ** **  **     **     ** *** 
;  ****   ****  **  ** ****** ****** **  ** 
;===============================================================================	

.local
;===============================================================================
; DESTROY BRICKS - brick removal.
;===============================================================================
; Given an X Brick and Y Row number, locate the brick and mask out the 
; pixels using the BRICK_MASK_TABLE.
; The table provides AND mask for three consecutive bytes, though 
; the third is not always needed it is present to simplify the code.
;===============================================================================
; INPUT:
; X == Brick number, 0 to 13
; Y == Row number, 0 to 7.
; Also uses:
; ZBRICK_BASE (ZEROPAGE_POINTER_8)  Base address of bricks on row.
;===============================================================================

DestroyBrick

	saveRegs ; Save regs so this is non-disruptive to caller

	; Setup ZBRICK_BASE from BRICK_BASE_LINE_TABLEs
	lda BRICK_CENTER_SCREEN_TABLE_LO,y
	sta ZBRICK_BASE 
	lda BRICK_CENTER_SCREEN_TABLE_HI,y
	sta ZBRICK_BASE+1
	
	; Multiply Brick number by 4 to get correct offset into the array
	txa
	asl a ; * 2
	asl a ; * 4
	tax
	
	lda BRICK_MASK_TABLE,x ; Get entry 0, the byte offset for this brick...
	tay                    ; Byte offset in Y for indirection below... 
	
	inx ; increment for entry 1, the first mask byte

	lda #3 ; need to do loop below three times
	sta M_TEMP1
	
?Loop_NextByteMask
	lda BRICK_MASK_TABLE,x ; Load mask
	and (ZBRICK_BASE),y    ; AND with pixel memory
	sta (ZBRICK_BASE),y    ; store updated pixels.

	iny                    ; increment for next memory offset	
	inx                    ; increment for next mask entry
	dec M_TEMP1             ; Loop counter
	bne ?Loop_NextByteMask ; No.  Do next byte of pixels.
	
	safeRTS ; restore regs for safe exit
	
.local
;===============================================================================
; CLEAR ALL SCREEN MEM
;===============================================================================
; Zero all 64-bytes of all the display lines.
; used once to init screen memory.
; 
; This is done to allow the code to declare screen memory
; using .ds instead of assembling storage per .dc directive.
;
; This would only be called once at initialization.
;===============================================================================
; 
;===============================================================================
; Write 64 zero bytes to each Row 
;===============================================================================

MainClearAllScreenRAM

	ldx #$3F
	lda #0
	
?LoopZeroBitmapToScreen	
	sta BRICK_LINE0,x
	sta BRICK_LINE1,x
	sta BRICK_LINE2,x
	sta BRICK_LINE3,x
	sta BRICK_LINE4,x
	sta BRICK_LINE5,x
	sta BRICK_LINE6,x
	sta BRICK_LINE7,x
	
	sta EMPTY_LINE,x
	
	dex
	bpl ?LoopZeroBitmapToScreen
	
	rts


.local
;===============================================================================
; MAIN CLEAR CENTER SCREEN
;===============================================================================
; Zero the center screen bitmap on all the screen rows.
;===============================================================================
; 
;===============================================================================
; Write 20 zero bytes to each Row at position +20 
;===============================================================================

MainClearCenterScreen

	ldx #19
	lda #0
	
?LoopZeroBitmapToScreen	
	sta BRICK_LINE0+23,x
	sta BRICK_LINE1+23,x
	sta BRICK_LINE2+23,x
	sta BRICK_LINE3+23,x
	sta BRICK_LINE4+23,x
	sta BRICK_LINE5+23,x
	sta BRICK_LINE6+23,x
	sta BRICK_LINE7+23,x
	
	dex
	bpl ?LoopZeroBitmapToScreen
	
	rts
	
	
.local
;===============================================================================
; MAIN COPY GAME OVER
;===============================================================================
; Copy the GAME OVER bitmap to all the screen rows.
;===============================================================================
; 
;===============================================================================
; Copy 20 bytes from GAMEOVER_LINEs to each Row at position +20 
;===============================================================================

MainCopyGameOver

; Copy associated color table.

	ldx #7
	
?LoopCopyColorTable
	lda TABLE_COLOR_GAME_OVER,x
	sta BRICK_CURRENT_COLOR,x
	
	dex
	bpl ?LoopCopyColorTable
	
; Copy screen data

	ldx #19
	
?LoopCopyGameOverToScreen	
	lda GAMEOVER_LINE0,x
	sta BRICK_LINE0+23,x

	lda GAMEOVER_LINE1,x
	sta BRICK_LINE1+23,x

	lda GAMEOVER_LINE2,X
	sta BRICK_LINE2+23,x

	lda GAMEOVER_LINE3,x
	sta BRICK_LINE3+23,x

	lda GAMEOVER_LINE4,X
	sta BRICK_LINE4+23,x

	lda GAMEOVER_LINE5,X
	sta BRICK_LINE5+23,x

	lda GAMEOVER_LINE6,X
	sta BRICK_LINE6+23,x

	lda GAMEOVER_LINE7,X
	sta BRICK_LINE7+23,x
	
	dex
	bpl ?LoopCopyGameOverToScreen
	
	rts
	

.local
;===============================================================================
; MAIN COPY LOGO
;===============================================================================
; Copy the LOGO bitmap to all the screen rows.
;===============================================================================
; 
;===============================================================================
; Copy 20 bytes from LOGO_LINEs to each Row at position +20 
;===============================================================================

MainCopyLogo

; Copy associated color table.

	ldx #7
	
?LoopCopyColorTable
	lda TABLE_COLOR_TITLE,x
	sta BRICK_CURRENT_COLOR,x
	
	dex
	bpl ?LoopCopyColorTable
	
; Copy screen data

	ldx #19
	
?LoopCopyBitmapToScreen	
	lda LOGO_LINE0,X
	sta BRICK_LINE0+23,x

	lda LOGO_LINE1,X
	sta BRICK_LINE1+23,x

	lda LOGO_LINE2,X
	sta BRICK_LINE2+23,x

	lda LOGO_LINE3,X
	sta BRICK_LINE3+23,x

	lda LOGO_LINE4,X
	sta BRICK_LINE4+23,x

	lda LOGO_LINE5,X
	sta BRICK_LINE5+23,x

	lda LOGO_LINE6,X
	sta BRICK_LINE6+23,x

	lda LOGO_LINE7,X
	sta BRICK_LINE7+23,x
	
	dex
	bpl ?LoopCopyBitmapToScreen
	
	rts
	

.local
;===============================================================================
; MAIN COPY BRICKS
;===============================================================================
; Copy the Brick bitmap to all the screen rows.
;===============================================================================
; 
;===============================================================================
; Copy 20 bytes from BRICK_LINE_MASTER to each Row at position +20 
;===============================================================================

MainCopyBricks

; Copy associated color table.

	ldx #7
	
?LoopCopyColorTable
	lda TABLE_COLOR_BRICKS,x
	sta BRICK_CURRENT_COLOR,x
	
	dex
	bpl ?LoopCopyColorTable
	
; Copy screen data

	ldx #19
	
?LoopCopyBitmapToScreen	
	lda BRICK_LINE_MASTER,x
	
	sta BRICK_LINE0+23,x
	sta BRICK_LINE1+23,x
	sta BRICK_LINE2+23,x
	sta BRICK_LINE3+23,x
	sta BRICK_LINE4+23,x
	sta BRICK_LINE5+23,x
	sta BRICK_LINE6+23,x
	sta BRICK_LINE7+23,x
	
	dex
	bpl ?LoopCopyBitmapToScreen
	
	rts
	

.local
;===============================================================================
; MAIN SET CENTER TARGET SCROLL
;===============================================================================
; Setup Scroll positions to bring in a new screen of graphics (in the 
; center position).
; The current position need not be left/right screen.  This will be forced.
; Determine Horizontal Scroll Directions for each line.
; Set Current HSCROL and Display List LMS to the left or right screen (per row). 
; Set Target HSCROL and Display List LMS to the center screen (per row).
;===============================================================================
; Uses MainGetRandomScroll to establish the following:
; M_DIRECTION_INDEX == Direction index
; M_SPEED_INDEX == Speed index
; M_DELAY_INDEX == Delay index
; also uses:
; M_TEMP_PHA == temporary save the X register/current row
;===============================================================================
; * The difference between Bricks entering the screen and the 
;   Logo or GameOver graphics is that during normal gameplay 
;   the Bricks do not have an exit transition to move the 
;   graphics off to show blank screen data. However, in both 
;   cases the graphics moving on screen are in the center 
;   position.
; * When all the bricks are removed from the screen the next full 
;   board must transition in place as soon as possible.  
; * By default, the at rest/static/target position of the screen is 
;   always the center screen at LMS offset +20 on every line.
; * The expectation for Bricks is that the center screen is currently
;   empty and the new screen bricks are being introduced.
; * Therefore this routine can be used to transition graphics to the 
;   screen from the blank screen after Logo or GameOver, or from 
;   the blank center screen after all bricks are destroyed, because
;   this routine forces the target to the Center screen and the 
;   current/origin to left or right screens per the canned scrolling
;   randomizer. 
; * Placing a new screen of bricks requires updating screen data
;   and setting the lines to left or right line positions while
;   the bricks are NOT being displayed.  
;   (This should not be too hard since the bulk of the brick section 
;    is monopolized by a long running DLI, so MAIN line code won't get 
;    much working time until after the DLI.)
; * To animate bricks
;   - reset the display to the off screen left or right positions,
;   - set all scroll parameters,
;   - set Target to the center screen,
;   - (write the bitmap into the center position ASAP. Not done here) 
;===============================================================================

MainSetCenterTargetScroll

	jsr MainGetRandomScroll      ; Setup PARAMS for Direction, Speed, Delay.
	
	saveRegs ; Save regs so this is non-disruptive to caller
	
?BeginInitScrollLoop
	ldx #0  ; Brick Row. 0 to 7. (otherwise the TABLES need to be flipped in reverse)

?InitRowPositions
	stx M_TEMP_PHA ; Row                ; Need to reload X later
	
	lda BRICK_SCREEN_CENTER_LMS_TARGET,x ; The center screen LMS low byte
	sta BRICK_SCREEN_TARGET_LMS,x       ; Set for the row.

	lda #0  ; This is always 0
	sta BRICK_CURRENT_HSCROL,x          ; Set for the current row.
		
	ldy M_DIRECTION_INDEX ; Direction
	lda TABLE_CANNED_BRICK_DIRECTIONS,y ; Get direction per canned list for the row.
	sta BRICK_SCREEN_DIRECTION,x        ; Save direction -1, +1 for row.
	
	tay
	iny                              ; Now direction is adjusted to 0, 2

; Get Starting LMS position per scroll direction.

	cpy #0 ; 
	bne ?Do_Moving_Screen_Right
	
	lda BRICK_SCREEN_RIGHT_LMS_TARGET,x ; Left means starting from Right Screen 
	jmp ?Prepare_For_LMS_Update
	
?Do_Moving_Screen_Right
    lda BRICK_SCREEN_LEFT_LMS_TARGET,x ; Right means starting from Left Screen 
      
?Prepare_For_LMS_Update
    pha  ; Need to save A which holds the new LMS until X is correct offset into display list
   
    lda BRICK_LMS_OFFSETS,x         ; Get Display List LMS low byte offset per the row.
	tax
	
	pla ; Get new LMS value back.  And store into display list.
	
	sta DL_BRICK_BASE,x             ; Set low byte of LMS to move row

	ldx M_TEMP_PHA ; Row            ; Get the row number back.

	ldy M_SPEED_INDEX ; Speed
	lda TABLE_CANNED_BRICK_SPEED,y  ; Get speed per canned list for the row.
	sta BRICK_SCREEN_HSCROL_MOVE,x  ; Set for the current row.
	
	ldy M_DELAY_INDEX ; Delay
	lda TABLE_CANNED_BRICKS_DELAY,y ; Get delay per canned list for the row.
	sta BRICK_SCREEN_MOVE_DELAY,x   ; Set for the current row.
	
	inx                             ; Increment to the next row.
	cpx #8                          ; Reached the end?
	beq ?End_SetCenterTargetScroll   ; Yes. Exit.
	
	; Not the end.  Increment everything else.
    
	inc M_DIRECTION_INDEX ; Direction index
	inc M_SPEED_INDEX ; Speed index
	inc M_DELAY_INDEX ; Delay index
    
	jmp ?InitRowPositions         ; Loop again.

?End_SetCenterTargetScroll

	inc BRICK_SCREEN_START_SCROLL  ; Signal VBI to start screen movement.
	
	safeRTS ; restore regs for safe exit


.local
;===============================================================================
; MAIN SET CLEAR TARGET SCROLL
;===============================================================================
; Setup Scroll positions to bring in an empty screen display.
; The current position should be the center screen.
; Determine Horizontal Scroll Directions for each line. 
; Set Target HSCROL and Display List LMS to the left or right screen (per row).
;===============================================================================
; Uses MainGetRandomScroll to establish the following:
; M_DIRECTION_INDEX == Direction index
; M_SPEED_INDEX == Speed index
; M_DELAY_INDEX == Delay index
;===============================================================================
; * The difference between Bricks entering the screen and the 
;   Logo or GameOver graphics is that during normal gameplay 
;   the Bricks do not have an exit transition to move the 
;   graphics off to show blank screen data. However, in both 
;   cases the graphics moving on screen are in the center 
;   position.  
; * The expected starting point for screen position is 
;   always the center screen at LMS offset +20 on every line.
; * Placing a new screen of bricks requires updating screen data
;   and setting the lines to left or right line positions while
;   the bricks are NOT being displayed.  
;   (This should not be too hard since the bulk of the brick section 
;    is monopolized by a long running DLI, so MAIN line code won't get 
;    much working time until after the DLI.)
; * To clear bricks/title/game over text
;   - set all scroll parameters,
;   - set Target to the left or right per random choices, 
;===============================================================================

MainSetClearTargetScroll

	jsr MainGetRandomScroll          ; Setup PARAMS for Direction, Speed, Delay.
	
	saveRegs ; Save regs so this is non-disruptive to caller
	
?BeginInitScrollLoop
	ldx #0  ; Brick Row. 0 to 7. (otherwise the TABLES need to be flipped in reverse)

?InitRowPositions	
	stx M_TEMP_PHA ; Row               ; Need to reload X later

    lda #0 ; This is always 0.
	sta BRICK_CURRENT_HSCROL,x   ; Set for the current row.
	
	ldy M_DIRECTION_INDEX ; Direction table
	lda TABLE_CANNED_BRICK_DIRECTIONS,y ; Get direction per canned list for the row.
	sta BRICK_SCREEN_DIRECTION,x        ; Save direction -1, +1 for row.

	tay
	iny                              ; Now direction is adjusted to 0, 2

; moving from Center to Left or Right screens.

; Get Ending LMS position per scroll direction.

	cpy #0 ; 
	bne ?Do_Moving_Screen_Right
	
	lda BRICK_SCREEN_LEFT_LMS_TARGET,x ; Left means going to the Left Screen 
	jmp ?Do_Target_Update
	
?Do_Moving_Screen_Right
    lda BRICK_SCREEN_RIGHT_LMS_TARGET,x ; Right means going to the Right Screen 
 
?Do_Target_Update
	sta BRICK_SCREEN_TARGET_LMS,x    ; Set target

; For Safety, force the LMS to the Center screen. 
; (Really should not be necessary.) 

	lda BRICK_SCREEN_CENTER_LMS_TARGET,x ; The center screen LMS low byte
	
	pha  ; Need to save A which holds the new LMS until X is correct offset into display list
	
    lda BRICK_LMS_OFFSETS,x      ; Get Display List LMS low byte offset per the row.
	tax
	
	pla ; Get new LMS value back.  And store into display list.
	
	sta DL_BRICK_BASE,x              ; Set low byte of LMS to move row
	
	ldx M_TEMP_PHA ; Row             ; Get the row number back.
	
	ldy M_SPEED_INDEX                ; Y = Speed index
	lda TABLE_CANNED_BRICK_SPEED,y   ; Get speed per canned list for the row.
	sta BRICK_SCREEN_HSCROL_MOVE,x   ; Set for the current row.
	
	ldy M_DELAY_INDEX                     ; Y = Delay index
	lda TABLE_CANNED_BRICKS_DELAY,y  ; Get delay per canned list for the row.
	sta BRICK_SCREEN_MOVE_DELAY,x    ; Set for the current row.
	
	inx                              ; Increment to the next row.
	cpx #8                           ; Reached the end?
	beq ?EndSetClearTargetScroll     ; Yes. Exit.
	
	; Not the end.  Increment everything else.
    
	inc M_DIRECTION_INDEX                     ; Direction index
	inc M_SPEED_INDEX                     ; Speed index
	inc M_DELAY_INDEX                     ; Delay index
    
	jmp ?InitRowPositions            ; Loop again.

?EndSetClearTargetScroll

	inc BRICK_SCREEN_START_SCROLL    ; Signal VBI to start screen movement.
	
	safeRTS ; restore regs for safe exit


.local
;===============================================================================
; MAIN GET RANDOM SCROLL
;===============================================================================
; Determine random scroll parameters.  Each value is a random 
; selection resulting in the base offest into a Canned table 
; of values providing data for each row.  The index to the
; randomly chosen row is saved by this routine.
;===============================================================================
; MODIFIES/OUTPUT:
; M_DIRECTION_INDEX == Direction index
; M_SPEED_INDEX == Speed index
; M_DELAY_INDEX == Delay index
;===============================================================================
;
;===============================================================================

MainGetRandomScroll

	saveRegs ; Save regs so this is non-disruptive to caller

	lda RANDOM                   ; choose random canned direction table index.
	and #$38                     ; Resulting value 00, 08, 10, 18, 20, 28, 30, 38
	sta M_DIRECTION_INDEX ; Direction     ; save to use later.
	
	lda RANDOM                   ; choose random canned speed table entries.
	and #$18                     ; Resulting value 00, 08, 10, 18
	sta M_SPEED_INDEX ; Speed         ; save to use later.
	
	bne ?SkipChooseScrollDelay   ; If Speed is not 0 then don't pick random delay.
	
	lda M_DIRECTION_INDEX ; Direction     ; If direction is not 00 or 08 then don't pick random delay.
	cmp #$08
	bcs ?SkipChooseScrollDelay
	
	lda RANDOM
	and #$38                     ; Resulting value 00, 08, 10, 18, 20, 28, 30, 38
	sta M_DELAY_INDEX ; Delay         ; save to use later.
	
	clc
	bcc ?ExitGetRandomScroll
	
?SkipChooseScrollDelay
	lda #0
	sta M_DELAY_INDEX ; Delay         ; save to use later.

?ExitGetRandomScroll
	safeRTS ; restore regs for safe exit

	
	

	
	
	
.local
;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
;   MAIN GAME CONTROL LOOP
;===============================================================================

;===============================================================================
; Program Start/Entry.  This address goes in the DOS Run Address.
;===============================================================================

PRG_START 

; 1) a) insure all screen memory is 0.  
;       (May be smart to zero/init other things, too.)

	jsr MainClearAllScreenRAM

	
; 1) b) Initialize graphics/screen

	jsr Setup  ; setup graphics

; 1) c); Enable Features....

;	lda #1
;	jsr MainSetTitle

;	lda #1
;	sta ENABLE_THUMPER

	lda #1
	sta ENABLE_BOOM

	
; 1) d) Start Vertical Blank Interrupt

	jsr Set_VBI
	

; 2 is NOT NEEDED.  Default initialized position is left/screen 1:

; 2) a) immediate/force all display LMS to off screen (left/screen 1 postition).
; 2) b) Wait for movement to occur:
	
;	jsr WaitFrame 
	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; 10 second delay on startup just to give me 
; time to start the screen recording.

;	ldx #240
;	jsr WaitFrames
;	ldx #240
;	jsr WaitFrames
;	ldx #240
;	jsr WaitFrames
	

    
	
FOREVER

; ***************
; TITLE 
; ***************
		
; 3) a) Load BREAKOUT graphics to off screen (which is currently center/screen 2) 
; 3) b) load breakout color table

; In final version code may need to verify current scanline 
; VCOUNT value is below the playfield before doing the copy.

;	jsr MainCopyLogo ; This does 3a and 3b.
	
; 4) Set new random Start positions for left/right scroll, Signal start scroll
; 5) a) Signal start Scroll to the VBI

;	jsr MainSetCenterTargetScroll ; This does 4 and 5a.

; 5) b) Wait for next frame.
; 5) c) wait until scroll movement completes

;	jsr WaitForScroll ; This does 5b and 5c.
	
; 6) Pause 2 seconds/120 frames

;	ldx #120
;	jsr WaitFrames

; ***************
; CLEAR TITLE     
; ***************
    
; 7) Set random destination to clear screen (left/screen 1 and right/screen 3)
; 8) a) Signal start Scroll to the VBI

	jsr MainSetClearTargetScroll ; this does 7 and 8a.

	; set the VBI Immediate move flag ASAP, before VBI can start moving...
	lda #1
	sta BRICK_SCREEN_IMMEDIATE_POSITION
	
	
; 8) b) Wait for frame.
; 8) c) wait until scroll movement completes

	jsr WaitForScroll ; This does 8b and 8c.

; 9) Clear center screen
;  Not needed, because it will be filled with bricks in just a moment...

; ***************
; PLAY BRICKS 1    
; ***************

; 10) a) Load BRICKS graphics to off screen (which is currently center/screen 2) and
; 10) b) load BRICKS color table

	jsr MainCopyBricks ; This does 10a and 10b.
	
; 11) Set new random Start positions for left/right scroll, Signal start scroll
; 12) a) Signal start Scroll to the VBI

	jsr MainSetCenterTargetScroll ; This does 11 and 12a.

; 12) b) Wait for next frame.
; 12) c) wait until scroll movement completes

	jsr WaitForScroll ; This does 12b and 12c.

; 13) Pause 2 seconds/120 frames

	ldx #120
	jsr WaitFrames

; ***************
; CLEAR BRICKS 1    
; ***************

; 14) a) Loop X and Y. 
; 14) b) Erase a brick.
; 14) c) Pause to show brick deletion progress.
; 14) d) continue loop.

	jsr Diag_DestroyBricks1 ; 14a through 14d

; 15) a) Set random destination to clear screens (left/screen 1 and right/screen 3)
; 15) b) immediate/force all disply LMS to off screen (left/screen 1 postition) 

	jsr MainSetClearTargetScroll ; this does 15a and flags VBI to start moving.

	; set the VBI Immediate move flag ASAP, before VBI can start moving...
	lda #1
	sta BRICK_SCREEN_IMMEDIATE_POSITION
	
; 15) c) wait for movement to occur:

	jsr WaitForScroll ; This does 15c.

; ***************
; PLAY BRICKS 2    
; ***************

; 16) a) Load BRICKS graphics to off screen (which is currently center/screen 2) and
; 16) b) load BRICKS color table

	jsr MainCopyBricks ; This does 16a and 16b.

; 17) Set new random Start positions for left/right scroll, Signal start scroll
; 18) a) Signal start Scroll to the VBI

	jsr MainSetCenterTargetScroll ; This does 17 and 18a.

; 18) b) Wait for next frame.
; 18) c) wait until scroll movement completes

	jsr WaitForScroll ; This does 18b and 18c.

; 19) Pause 2 seconds/120 frames

	ldx #120
	jsr WaitFrames
	
; ***************
; CLEAR BRICKS 2    
; ***************

; 20) a) Loop X and Y. 
; 21) b) Erase a brick.
; 22) c) Pause to show brick deletion progress.
; 23) d) continue loop.

	jsr Diag_DestroyBricks2 ; 20a through 20d
	
; 21) a) Set random destination to clear screens (left/screen 1 and right/screen 3)
; 21) b) immediate/force all disply LMS to off screen (left/screen 1 postition) 

;	jsr MainSetClearTargetScroll ; this does 21a and flags VBI to start moving.

	; set the VBI Immediate move flag ASAP, before VBI can start moving...
;	lda #1
;	sta BRICK_SCREEN_IMMEDIATE_POSITION
	
; 21) c) wait for movement to occur:

;	jsr WaitForScroll ; This does 21c.

; ***************
; GAME OVER 
; ***************
	
; 22) a) Load GAME OVER graphics to off screen (which is currently center/screen 2) and
; 22) b) load breakout color table

;	jsr MainCopyGameOver ; This does 22a and 22b.
	
; 23) Set new random Start positions for left/right scroll, Signal start scroll
; 24) a) Signal start Scroll to the VBI

;	jsr MainSetCenterTargetScroll ; This does 23 and 24a.

; 24) b) Wait for next frame.
; 24) c) wait until scroll movement completes

;	jsr WaitForScroll ; This does 24b and 24c.

; 25) Pause 2 seconds/120 frames

;	ldx #120
;	jsr WaitFrames
	
; ***************
; CLEAR GAME OVER     
; ***************

; 26) Set random destination to clear screen (left/screen 1 and right/screen 3)
; 27) a) Signal start Scroll to the VBI

;	jsr MainSetClearTargetScroll ; this does 26 and 27a.

; 27) b) Wait for frame.
; 28) c) wait until scroll movement completes

;	jsr WaitForScroll ; This does 27b and 27c.

; 29) Clear center screen

;	jsr MainClearCenterScreen ; and 29.
	
;	jsr WaitFrame ; Wait for VBI to run.



	jmp FOREVER ; And again.  (and again) 




.local
;===============================================================================
;   Basic setup. Stop sound. Create screen.
;===============================================================================
;===============================================================================
; **   **   **    ******  **  **
; *** ***  ****     **    *** **
; ******* **  **    **    ******
; ** * ** **  **    **    ******
; **   ** ******    **    ** ***
; **   ** **  **  ******  **  ** 
;===============================================================================

;===============================================================================
;   Basic setup. Stop sound. Create screen.
;===============================================================================

Setup
; Make sure 6502 decimal mode is not set -- not  necessary, 
; but it makes me feel better to know this is not on.
	cld

	lda #0     ; Off. No DMA for display list, display, Player/Missiles.
	sta SDMCTL ; Display DMA control 
	
;	sta TITLE_HPOSP0 ; Zero horizontal position for Player used as Title character

	; Be clean and tidy.  Move P/M off screen.

	ldx #7
?Zero_PM_HPOS        ; 0 to 7, Zero horizontal position registers for P0-3, M0-3.
	sta HPOSP0,x
	dex
	bpl ?Zero_PM_HPOS

	; Be clean and tidy II. Set normal sizes.

	lda #PM_SIZE_NORMAL ; Reset size for Players

	ldx #3
?Normal_PM_Size
	sta SIZEP0,x
	dex
	bpl ?Normal_PM_Size
	
	lda #~01010101 ; 01, normal size for each missile.
	sta SIZEM
	
	lda #0
	sta GPRIOR       ; Zero GTIA Priority

	sta GRACTL       ; Turn off GTIA P/M data graphics control 

	lda #NMI_VBI     ; Turn OFF DLI leaving only VBI on.
	sta NMIEN
	
;===============================================================================
	jsr WaitFrame ; Wait for vertical blank updates from the shadow registers.
;===============================================================================

	; Set shadow register/defaults for the top of the screen.
	
	lda #<DISPLAY_LIST ; Set Display List address
	sta SDLSTL
	lda #>DISPLAY_LIST
	sta SDLSTH
	
	lda #<DISPLAY_LIST_INTERRUPT ; Set the DLI Vector
	sta VDSLST
	lda #>DISPLAY_LIST_INTERRUPT
	sta VDSLST+1
	;
	; Turn on Display List DMA
	; Turn on Player/Missile DMA
	; Set Playfield Width Narrow (a temporary thing for the title section)
	; Set Player/Missile DMA to 1 Scan line resolution/updates
	;
	lda #[ENABLE_DL_DMA|ENABLE_PM_DMA|PLAYFIELD_WIDTH_NARROW|PM_1LINE_RESOLUTION]
	sta SDMCTL ; Display DMA control
	
	lda #>PLAYER_MISSILE_BASE ; Set Player/Missile graphics memory base address.
	sta PMBASE
	;
	; Set Missiles = 5th Player (COLPF3)
	; Set Priority with P0/P1 on top, then Playfield, then PM2/PM3 on bottom.
	;
	lda #[FIFTH_PLAYER|~0000010]  
	sta GPRIOR

	lda #[ENABLE_PLAYERS|ENABLE_MISSILES]
	sta GRACTL ; Turn on GTIA P/M data graphics Control 

	lda #[NMI_DLI|NMI_VBI] ; Turn ON DLI and VBI Interrupt flags 
	sta NMIEN
	
	lda #>CHARACTER_SET_01 ; Character set for title
	sta CHBAS
	;
	; Draw vertical Thumpers
	;
	ldx #MIN_PIXEL_Y
	lda #$80
?Init_Vertical_Thumpers
	sta PMADR_BASE3,x
	sta PMADR_BASE2,x
	inx
	cpx #MAX_PIXEL_Y
	bne ?Init_Vertical_Thumpers

	rts 
 

.local
;===============================================================================
; MAIN SET TITLE
;===============================================================================
; Turn on/off the Title animation.
;===============================================================================
; Input:
; A = Value to write to TITLE_STOP_GO
;===============================================================================
; Set flag referenced by VBI to start/stop animation of the Title line.
;===============================================================================

MainSetTitle

;	sta TITLE_STOP_GO
	
	rts


;===============================================================================
; WAIT FRAME - wait for vertical blank
;===============================================================================
; The Atari OS  maintains a clock that ticks every vertical 
; blank.  So, when the clock ticks the frame has started.

WaitFrame

	saveRegs ; Save regs so this is non-disruptive to caller

	lda RTCLOK60			; get frame/jiffy counter
	
WaitTick60
	cmp RTCLOK60			; Loop until the clock changes
	beq WaitTick60

;; if the real-time clock has ticked off approx 29 seconds,  
;; then set flag to notify other code.

;	lda RTCLOK+1;
;	cmp #7	;; Has 29 sec timer passed?
;	bne skip_29secTick ;; No.  So don't flag the event.
;	inc auto_next	;; flag the 29 second wait
;	jsr reset_timer

skip_29secTick

;	lda mr_roboto ;; in auto play mode?
;	bne ?Exit_waitFrame ;; Yes. then exit to skip playing sound.

	lda #$00  ;; When Mr Roboto is NOT running turn off the "attract"
	sta ATRACT ;; mode color cycling for CRT anti-burn-in
    
;	jsr AtariSoundService ;; Play sound in progress if any.


;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

; Write selected byte values to diagnostic line on screen.

;	.sbyte " JF SS SI VM H0 H1 H2 H3 H4    DE SP DI "

;	.sbyte " JF SS SI VM  H0 1 2 3 4 5 6 7  DE SP DI"

;	.sbyte " JF EB    RQ    RB CY BB HP SZ CP       "
	
	mDebugByte RTCLOK60,              1 ; JF
	
	mDebugByte ENABLE_BOOM,           4 ; EB

	mDebugByte BOOM_REQUEST,         10 ; RQ
	
	mDebugByte BOOM_REQUEST_BRICK,   16 ; RB

	mDebugByte BOOM_1_CYCLE,         19 ; CY

	mDebugByte BOOM_1_BRICK,         22 ; BB

	mDebugByte BOOM_1_HPOS,          25 ; HP

	mDebugByte BOOM_1_SIZE,          28 ; SZ

	mDebugByte BOOM_1_COLPM,         31 ; CP


	

;===============================================================================



?Exit_waitFrame

	safeRTS ; restore regs for safe exit

	rts



.local	
;===============================================================================
; ****   ******   **    *****
; ** **    **    ****  **  
; **  **   **   **  ** **
; **  **   **   **  ** ** ***
; ** **    **   ****** **  **
; ****   ****** **  **  *****
;===============================================================================

;DIAG_TEMP1 = PARAM_93 ; = $d0 ; DIAG_TEMP1

;---------------------------------------------------------------------
; Write hex value of a byte to the DIAG1 screen line.
; INPUT:
; A = byte to write
; Y = starting position.
;---------------------------------------------------------------------
DiagByte

	sta DIAG_TEMP1       ; store the byte to retrieve later

	saveRegs ; Save regs so this is non-disruptive to caller

	lda DIAG_TEMP1
	
	lsr  ; divide by 16 to shift it into the low nybble ( value of 0-F)
	lsr
	lsr
	lsr
	tax 
	lda ?NYBBLE_TO_HEX,x  ; simplify. no math. just lookup table.

	sta DIAG1,y           ; write into screen RAM.
	
	lda DIAG_TEMP1        ; re-fetch the byte to display

	and #$0F              ; low nybble is second character
	tax
	lda ?NYBBLE_TO_HEX,x  ; simplify. no math.  just lookup table.

	iny
	sta DIAG1,y

	safeRTS ; restore regs for safe exit

?NYBBLE_TO_HEX ; hex binary values 0 - F in internal format
	.sbyte "0123456789ABCDEF"

	
	
;===============================================================================
; WAIT FRAMES - wait for X vertical blanks.
;===============================================================================
; For diagnostics we need a longer delay for timing purposes.
; This may not have a purpose in the final game, since everything
; should be expected to cycle every frame and maintain states
; if it is delayed or not.
;===============================================================================
; INPUT
; X == Number of frames to wait.  
;      Should be 1 to 255.
;      1 would be the same as calling WaitFrame directly
;      0 would cause wait for 256 frames.
;===============================================================================

WaitFrames ; Frames, plural.

	jsr WaitFrame  ; Do-Nothing loop to wait for jiffy counter change
	
	dex            ; frame count - 1
	bne WaitFrames ; >0 is not done.

	rts

	
;===============================================================================
; WAIT FOR (VBI) SCROLL
;===============================================================================
; The program must sit still and monitor the VBI's scrolling activity
; only for diagnostic purposes. 
; This would not have a purpose in the final game, since all parts
; should be expected to cycle every frame and maintain states
; if it is delayed or not.
;===============================================================================
; INPUT
; X == Number of frames to wait.  
;      Should be 1 to 255. 
;      0 would cause wait for 256 frames.
;===============================================================================

WaitForScroll

	jsr WaitFrame              ; Wait for the next VBI to finish.

	lda BRICK_SCREEN_IN_MOTION ; Is the VBI still moving the lines?.

	bne WaitForScroll          ; Yes.  Wait again. 
	
	rts

	
;===============================================================================
; DIAG DESTROY BRICKS - looping brick by brick destruction.
;===============================================================================
; Cycle through all the brick positions.
; Mask out the brick to remove it from the screen.
; Wait a short time (fraction of a second/several frames) 
; Continue loop until all positions are gone.
;===============================================================================
; Since there is no ball bouncing here there are no Player X and Y 
; coordinates to convert into brick positions. Mechanically, this 
; function is operating after coordinate conversion via  
; BALL_XPOS_TO_BRICK_TABLE and BALL_YPOS_TO_BRICK_TABLE.
;===============================================================================
; Destroy bricks column by column
;===============================================================================


Diag_DestroyBricks1

	ldx #10 ; Bricks in the row. 13 to 0

?Next_Brick

	ldy #7 ; Number of rows,  7 to 0

?Next_Row

	jsr DestroyBrick ; Remove Brick at X, Y position
	
    ; --------------------------------
	txa                       ; Transfer Brick number to Accumulator
	sta BOOM_REQUEST_BRICK,y  ; Store brick number in the boom request for this row
	lda #1                    ; Raise flag to VBI that this row has a brick 
	sta BOOM_REQUEST,y        ; ready to enter in the boom cycle animations.
	; --------------------------------
	
	dex
	dex 
	
	txa              ; save brick number temporarily.
	ldx #5
	jsr WaitFrames   ; Pause for X frames
	tax              ; get Brick number back.

    tya 
    eor #~00000111
    tay
    
	jsr DestroyBrick ; Remove Brick at X, Y position
	
    ; --------------------------------
	txa                       ; Transfer Brick number to Accumulator
	sta BOOM_REQUEST_BRICK,y  ; Store brick number in the boom request for this row
	lda #1                    ; Raise flag to VBI that this row has a brick 
	sta BOOM_REQUEST,y        ; ready to enter in the boom cycle animations.
	; --------------------------------

    tya 
    eor #~00000111
    tay
    
	inx
	inx
	
	dey
	bpl ?Next_Row    ; Rows 7 to 0

	dex
	dex
	dex
	dex
	
	bpl ?Next_Brick  ; Bricks 13 to 0	

	; ------------------------------
	; Part TWO
	; ------------------------------

	ldx #13 ; Bricks in the row. 13 to 0

?Next_Brick_Again

	ldy #7 ; Number of rows,  7 to 0

?Next_Row_Again

	jsr DestroyBrick ; Remove Brick at X, Y position
	
    ; --------------------------------
	txa                       ; Transfer Brick number to Accumulator
	sta BOOM_REQUEST_BRICK,y  ; Store brick number in the boom request for this row
	lda #1                    ; Raise flag to VBI that this row has a brick 
	sta BOOM_REQUEST,y        ; ready to enter in the boom cycle animations.
	; --------------------------------
	
	dex
	dex 
	
	txa              ; save brick number temporarily.
	ldx #5
	jsr WaitFrames   ; Pause for X frames
	tax              ; get Brick number back.

    tya 
    eor #~00000111
    tay
    
	jsr DestroyBrick ; Remove Brick at X, Y position
	
    ; --------------------------------
	txa                       ; Transfer Brick number to Accumulator
	sta BOOM_REQUEST_BRICK,y  ; Store brick number in the boom request for this row
	lda #1                    ; Raise flag to VBI that this row has a brick 
	sta BOOM_REQUEST,y        ; ready to enter in the boom cycle animations.
	; --------------------------------

    tya 
    eor #~00000111
    tay
    
	inx
	inx
	
	dey
	bpl ?Next_Row_Again    ; Rows 7 to 0

	dex
	dex
	dex
	dex
	
	bpl ?Next_Brick_Again  ; Bricks 13 to 0	

	rts


;===============================================================================
; DIAG DESTROY BRICKS - looping brick by brick destruction.
;===============================================================================
; Same function as above destroying random bricks.
;===============================================================================

.local
Diag_DestroyBricks2

	lda #0
	sta V_TEMP

Loop_Destroy2	
	lda RANDOM
	and #~00000111
    tay
    
Try_Brick_Again
	lda RANDOM
	and #~00001111
	cmp #15
	bcs Try_Brick_Again
	tax

	jsr DestroyBrick ; Remove Brick at X, Y position
	
    ; --------------------------------
	txa                       ; Transfer Brick number to Accumulator
	sta BOOM_REQUEST_BRICK,y  ; Store brick number in the boom request for this row
	lda #1                    ; Raise flag to VBI that this row has a brick 
	sta BOOM_REQUEST,y        ; ready to enter in the boom cycle animations.
	; --------------------------------
	
	ldx #3
	jsr WaitFrames   ; Pause for X frames

	inc V_TEMP
	bne Loop_Destroy2 ; 256 times.   when it is 0 again it ends.

	rts


;===============================================================================
;   PROGRAM_INIT_ADDRESS
;===============================================================================
; Atari uses a structured executable file format that 
; loads data to specific memory and provides an automatic 
; run address.
;===============================================================================
; Store the program start location in the Atari DOS RUN Address.
; When DOS is done loading the executable it will automatically
; jump to the address placed in the DOS_RUN_ADDR.
;===============================================================================
;
	*=DOS_RUN_ADDR
	.word PRG_START

;===============================================================================

	.end ; finito
 
;===============================================================================
  
