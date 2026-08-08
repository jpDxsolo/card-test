class_name Deck

## Builds and shuffles decks. Deterministic by seed: the same seed always
## produces the same order. That is what makes a deal reproducible, and in M7
## it is what lets a deal be identified -- and solved -- by seed alone.

static func build(ruleset: Ruleset) -> PackedInt32Array:
	match ruleset.deck_composition:
		Ruleset.DeckType.STANDARD_52:
			var cards := PackedInt32Array()
			cards.resize(Card.COUNT)
			for i in Card.COUNT:
				cards[i] = i
			return cards
	push_error("Deck: composition %d not implemented" % ruleset.deck_composition)
	return PackedInt32Array()


static func shuffled(ruleset: Ruleset, deal_seed: int) -> PackedInt32Array:
	var cards := build(ruleset)
	var rng := RandomNumberGenerator.new()
	rng.seed = deal_seed

	# Fisher-Yates by hand rather than Array.shuffle(), which draws from the
	# global RNG and would make deals unreproducible.
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	return cards
