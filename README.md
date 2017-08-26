# GECE-parts
Test/Demo GECE components individually to reduce development/debugging complexity.
 
 
=============================================================

Breakout Title Line 

=============================================================

[![TitleScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-title-pic.png)](#features)

Video Here: https://youtu.be/UVcj-sRZLmk

The letters for the individual characters fly in from the right, one at a time to spell out the title.
Four raster bar/gradient color cycles move across the eight characters the entire time they are visible. 
After enjoying the title for a couple seconds the title vertically fine scrolls up off the screen to disappear.
After a couple seconds of blank screen the animation repeats.

The characters are a custom font in Mode 6 text.  Each character is built of two, vertically-stacked characters with the  image occuping the middle 12 scan lines (6 in the top character, 6 in the bottom).  Since the characters are displayed spaced apart they also use all 8 horizontal color clocks of pixel real-estate in the character image.

Considering 12 visible scan lines with four independent raster bars that's potentially 48 visible colors in the title.

Horizontal fine scrolling is used to shift the lines by 4 color clocks to exactly center the text on the screen.

The character flying in is a Player object, which also carries the color gradient for the destination character.  From a technical perspective that means the code is executing FIVE raster bar/gradient color cycles applied per scan line.

Note that the gradient colors move consistently even during vertical scrolling and while the scrolling causes the characters' scan lines to disappear.

Very little is calculated.  Most activity results from iterating through data in tables -- Title Text values and positions, the equivalent character data offsets for the Player, fine scroll values, coarse scroll updates, raster bar/gradient color cyles, offsets to the color cycling when scan lines are being lost, etc.

The vertical coarse scrolling isn't even done by updating the LMS addresses.  Instead, the small section of the display list showing the title lines is implemented like a subroutine.  A Jump in the main display list goes to one of the Title display lists, and the end of the Title display list jumps back to the main display list.  Therefore only one byte of the Jump address in the main display list is updated to change the vertical coarse scroll state.




=============================================================

Breakout Border Bumpers

=============================================================

[![ThumperScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-thumper-pic.png)](#features)
 
Video Here: https://youtu.be/aOLbqgy6q6A

As the ball approaches the top or side borders the bumper force field charges up.  When the ball strikes the border bumper then the force field violently recoils.

Player/Missile objects provide the left and right sides bumper animations.

The top border is a series of animated playfield frames cycled through the display list.  Like the coarse scroll update in the Title section this is done with one update to a Jump instruction in the main display list that points to one of several small display lists showing different states of the bumper animation.

This looked weird when the code ran the animations at 60 fps.  I cut down the speed to one update every other frame which improved the perceived effect.   Still not thrilled with this.  The proximity part may get changed.




=============================================================

Breakout Bricks Playfield 

=============================================================

[![BricksScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-bricks-pic.png)](#features)
 
Video Here: https://youtu.be/K__BENVv9AQ

This is the playfield for the bricks in the breakout game.   The bricks playfield rows are 5 scan lines tall with two blank lines between each row of bricks.  Since the bricks are graphics they can be used to draw more than just bricks, such as the Game Over screen used here.

A DLI applies raster bar/gradient color to the bricks, so instead of one color, or 8 colors, there are 40 colors displayed.

The horizontal lines appearing above and below the bricks are part of the debugging/diagnostics to insure the playfield begins and ends at the correct lines on the screen.  They will not appear in the finished game, of course.

So, what graphics mode on the Atari is 5 scan lines tall?  The bricks are made of Mode C graphics which is 1 scan line tall, which provides 1 color pixels, and 160 color clocks/pixels per scan line.  Then how are the bricks 5 scan lines tall?  There's a trick here...  The VSCROL is manipulated to trick ANTIC into repeating the same line of graphics five times.  

This VSCROLL abuse provides a number of benefits:

1) it uses less DMA time than five separate instructions with LMS to redisplay the same line.  However, that's not so important here, because there is a DLI running for 56 continuous scan lines to manage the VSCROLL hack and provide raster bar/gradient color to the bricks.
2) There is only one line of graphics to manage for each row.  Manipulate one row of data, and all five scan lines show the change.
3) There is only one LMS address to modify to scroll the graphics.   When horizontal scrolling is added to the graphics only one LMS address per row needs to be updated for the coarse scroll. (8 total)  Using separate LMS instructions to build bricks 5 scan lines tall would look the same, but require five LMS address updates per row (40 total!) to accomplish horizontal coarse scrolling.




=============================================================

Breakout Bricks Playfield Scrolling

=============================================================

[![BricksScrollScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-bricks-scroll-pic.png)](#features)
 
Video Here: https://youtu.be/kLrhFrXUn2U

This is the next increment in playfield management in the breakout game.   Each of the bricks' rows can be controlled to scroll left or right independently at different speeds.  This demo shows scrolling transitions from the Breakout title screen, to a playfield of bricks, to a Game Over screen.  It also demonstrates the brick bitmap masking/removal works as expected.

The scrolling transitions have several variables chosen at random:  

* A variable delay may be added to each line before scrolling begins.

* The direction may be left or right.

* The speed may vary from 1 to 4 color clocks per frame.

The program includes several canned patterns for scrolling.  The speed of the bottom line in all patterns has no starting delay and always scrolls 4 pixels per frame to insure the new bottom row is correctly in place before the ball returns to strike a brick.

The horizontal lines appearing above and below the bricks are part of the debugging/diagnostics to insure the playfield begins and ends at the correct lines on the screen.  They will not appear in the finished game, of course.




=============================================================

Boom Bricks Playfield Animation

=============================================================

[![BricksBoomScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-breakout-bricks-boom.png)](#features)
 
Video Here: https://youtu.be/lIWNLIQB6A0

Another level up for the playfield. Brick destruction is animated.  When struck, the brick glows brightly and instantly expands slightly in size, then shrinks and fades away. 

This is done using two Players allowing two animations to occur at the same time.  Display list interrupts change positions and colors of the Players for each row allowing two exploding brick animations for each row. The actual animation images are updated during the vertical blank. 

Since the entire disappearing trick is done by Players and not playfield images, the playfield scrolling to introduce new bricks can begin while the animation is still playing. 

This is really overkill for the scope of Breakout.  Maybe the worst case for a maximum speed rebound from the top border could require two animations playing at the same time.  This module supports 16 simultaneous animations.  For all practical purposes the game could probably get by without the display list interrupts for each row and use only the two players to manage two simultaneous explosions.

There is a little display glitch I'm trying to work out.  The first scan line of the first frames of the expanded brick image are missing part of the image on the left most column of bricks. Not sure if this is a Display List Interrupt timing situation or if something else is messing up the image.  It somehow seems that brick column 0 is having corrupted image data copied for the animation cells... which seems impossible if it works for other columns.... thinking.... I'm thinking....

UPDATE:  Fixed some issues.  These changes are not included in the current video....

Turns out the display glitch is a DLI timing issue.   Too many things are being changed around one WSYNC and there's just not enough time to do everything.  If the WSYNC is moved to allow the positioning to work, then the colors are off.  Or the size is off.   All these things must be in sync to allow the exploding brick to look consistent in any position. 

One choice is to make the playfield more narrow -- twelve color clocks per brick would provide an extra 14 color clocks of time at the beginning of the line which may be enough.  That would require refactoring all of the playfield graphics.  Not looking forward to that.  Maybe in a later version after the game is completely functional.

If the logic implemented only one exploding brick per row, that would halve the data the DLI copies and it should work.  But, I want two exploding bricks per row, so I am discounting that option.

Alternatively, if there was an extra blank line between rows that would definitely provide the time to change all P/M values  However, that would make the playfield for bricks even taller, and I think it is already at the maximum height reasonable for the game considering all the other visual bells and whistles taking up space on the display.

The best choice for what is already in execution is to not use adjacent scan lines between rows. Cutting off the extra scan line of the exploding brick at the top and botton of the animation reduces the exploding brick to the same height as a normal brick , but the animation still begins with an expanded brick two color clocks wider. This blowup and shrink effect still looks acceptable in this way.  So, this is the option for the game.  (In this case the rows may be changed to have only one blank scan line between them which better compresses the playfield's vertical size -- maybe in a future edition.)

SIDE NOTE:  In the new debug version the brick gradient in the DLI is changed to a dark-to-light-to-dark pattern which looks better than the dark-to-light pattern.

