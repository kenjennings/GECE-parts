# GECE-parts
Test/Demo GECE components individually to reduce development/debugging complexity.

** Breakout Title Line **

[![TitleScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-title-pic.png)](#features)

Video Here: https://youtu.be/UVcj-sRZLmk

The letters for the individual characters fly in from the right, one at a time to spell out the title.
Four raster bar/gradient color cycles move across the eight characters the entire time they are visible. 
After enjoying the title for a couple second the title vertically fine scrolls up off the screen to disappear.
After a couple seconds of blank screen the animation repeats.

The characters are a custom font in Mode 6 text.  Each character is built of two vertically stacked characters with the  image occuping the middle 12 scan lines (6 in the top character, 6 in the bottom).  Since the characters are displayed spaced apart they also use all 8 horizontal color clocks of pixel real-estate in the character image.

Horizontal fine scrolling is used to shift the lines by 4 color clocks to exactly center the text on the screen.

The character flying in is a Player object, which also carries the color gradient for the destination character.  That means there are actually FIVE raster bar/gradient color cycles being applied per scan line.

Note that the gradient colors move consistently even during vertical scrolling and while scan lines are disappearing from the character.

Very little is calculated.  Most things are played back from tables -- Title Text values and positions.  The equivalent character data offsets for the Player, fine scroll values, coarse scroll updates, raster bar/gradient color cyles, offsets to the color cycling when scan lines are being lost, etc.

The vertical coarse scrolling isn't even done by updating the LMS addresses.   Instead, the small section of the display list showing the title lines is presented like a subroutine.   A Jump in the main display list goes to one of the Title display lists, and at the ehd of the title display list it jumps back to the main display list.   Only one byte of the Jump in the main display list is updated to change the vertical coarse scroll state.




** Breakout Border Bumpers Line **

[![ThumperScreenGrab](https://github.com/kenjennings/GECE-parts/blob/master/parts-thumper-pic.png)](#features)
 
Video Here: https://youtu.be/aOLbqgy6q6A

As the ball approaches the top or side borders the bumper force field charges up.  When the ball strikes the border bumper then the force field violently recoils.

The left and right sides are animated by manipulating Player/Missile objects.

The top border is a series of animated playfield frames cycled through the display list.  Like the coarse scroll update in the Title section this is done with one update to a Jump instruction in the main display list that points to one of several small display lists showing different states of the bumper animation.

This looked weird when the code ran the animations at 60 fps.  I cut down the speed to one update every other frame which improved the perceived effect.   Still not thrilled with this.  The proximity part may get changed.



