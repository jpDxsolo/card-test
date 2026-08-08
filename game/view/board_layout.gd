class_name BoardLayout

## Every on-screen rectangle for one viewport size, in pixels. The output of
## LayoutResolver.compute().
##
## Pure data, no Nodes: a layout can be computed and asserted against in a test
## without a scene tree, and BoardView can diff two of them to decide what moved.

enum Profile { LANDSCAPE, PORTRAIT }

## What a click landed on. Returned by LayoutResolver.hit_test().
enum Target { NONE, TABLEAU, WASTE, STOCK }

var profile: Profile = Profile.LANDSCAPE

## Pixel size of one card at this scale. Every rect below is exactly this size.
var card_size: Vector2 = Vector2.ZERO

var slots: Array[Rect2] = []      ## indexed by Slot.id
var stock: Rect2 = Rect2()
var wastes: Array[Rect2] = []
var foundation: Rect2 = Rect2()
