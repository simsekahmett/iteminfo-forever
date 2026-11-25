local _, ns = ...

-- The scrolls a mage deciphers with the Comprehension skill, by tier. Unlike
-- the other data files, this one is written by hand.
--
-- Which scroll comes out is decided by the server and not known beforehand:
-- each undeciphered scroll of a tier may turn into any of the tier's results.
-- The results were gathered by players, a scroll is only listed when at least
-- two sources agree on its tier.
ns.Data.scrollTiers = {
  { -- Comprehension 1
    from = { 211780, 211785, 211786, 211787 },
    into = { 274947, 275067, 275069, 213564, 215257 },
  },
  { -- Comprehension 15
    from = { 211784, 211853, 211854, 211855 },
    into = { 277485, 277486, 277487, 277488, 277489, 217495, 277483, 277484, 277490 },
  },
  { -- Comprehension 50
    from = { 213543, 213544, 213545, 213546, 213547 },
    into = { 277494, 277495, 277496, 277497, 277498, 277492, 277493, 277491, 213548, 217496 },
  },
  { -- Comprehension 175
    from = { 281015, 281016, 281017, 281018 },
    into = { 277499, 277500, 277501, 277502, 277503, 277504 },
  },
}
