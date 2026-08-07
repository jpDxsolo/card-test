class_name Card

## Cards are plain integers 0..51 — never objects. The solver will copy and hash
## game states by the million; integers keep that cheap.
##
##   suit = id / 13  ->  0 Hearts, 1 Diamonds, 2 Clubs, 3 Spades
##   rank = id % 13  ->  0 Ace .. 12 King
##
## Suit order is not arbitrary: it matches the card sheet's row order, so a card
## id maps straight to sheet coordinates with no lookup table. Changing this
## enum means re-checking CardTheme.

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }
const NONE := -1
const COUNT := 52
const RANKS_PER_SUIT := 13



static func make(suit: int, rank: int) -> int:
	return suit * RANKS_PER_SUIT + rank
	
static func suit_of(id: int) -> int:
	return id / RANKS_PER_SUIT

static func rank_of(id: int) -> int:
	return id % RANKS_PER_SUIT
	
## Pyramid value: Ace = 1 ... King = 13. The single place the game's ranking is
## encoded — everything downstream asks this rather than computing its own.
static func value_of(id: int) -> int:
	return rank_of(id) + 1
	
static func debug_name(id: int) -> String:
	const RANKS := ["A","2","3","4","5","6","7","8","9","10","J","Q","K"]
	const SUITS := ["H","D","C","S"]
	return RANKS[rank_of(id)] + SUITS[suit_of(id)]
