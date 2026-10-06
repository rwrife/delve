# Wing 1: The Silent Reliquary (content v2)

Original tomb setting; the map below is authored data, not a generated level. Engine tables live in `Packages/DelveKit/Sources/DelveKit/Resources/content-v2.json`; layered quest clues live in `quest-v2.json`. Version 1 remains unchanged for previously pinned ledgers. Version 2 is the source for **new** runs when the issue-4 exploration UI connects to the engine. The current bootstrap UI does not yet play the wing.

```
entrance — brazier-hall — sealed-vault — dust-corridor — fork
                                                        ├— blind-crypt — ossuary (false end)
                                                        ├— amber-alcove (bronze key)
                                                        ├— west-gallery — bell-niche (resonant bell)
                                                        └— [arch-door: bronze key] sentinel-arch
                                                             — echo-steps — stair-landing — reliquary
                                                             — [heart-door: bronze key + bell-lit] heart-chamber
```

Fifteen rooms, one wing, two keyed doors. The direct route through the false crypt terminates in the ossuary: there is no key there and no passage forward. Retrace through the fork, obtain the key from the alcove, ring the bell in its niche, then pass the arch and the sealed heart door. The switch works **only in its room**; the final door requires the key *and* the bell flag. Keys are collected on room entry; an opened door stays latched even if the bell is later toggled off. Every ordinary door is two-way. Deliberate backtracking is a puzzle step, not a softlock. The brazier is a location-bound, reversible atmospheric switch.

The crypt watcher has a fixed seven-step room cycle (blind-crypt, ossuary, blind-crypt, ossuary, blind-crypt, ossuary, ossuary); moving advances the step. The direct false-crypt visit **and return** are safe and recoverable. A longer alternate route can shift its phase so contact occurs; that requires a mandatory ledgered death event. The alcove-and-gallery detour used in the end-to-end test safely reaches the ossuary and its clue. Patrol contact/death is an intentional terminal **hazard**, not a puzzle lock. No random timing, wall-clock input, network, or hidden patrol state is used. Tests exercise both a recoverable direct dead-end and a fatal longer detour.

The quest deliberately withholds exact directions. The three layers are: listening to the stone, letting something answer, and looking beyond the last echo. Their `unknown → in_progress → achieved` states are derived only from validated ledger events. Visiting a location never fabricates a discovery: the player must ledger the clue event. A later goal stays unknown until its *own* first-evidence event appears, even if unrelated rooms have been visited. Death and retreat grant no completion.

## Content gate for wings 2–3

At app launch, `DelveApp.init` loads the bundled v2 table and quest files; the table loader invokes `GraphValidator.validate` before use. The same validator runs in Linux tests. It rejects malformed/duplicate rooms and doors, broken references, nonadjacent patrol jumps, structural disconnection, unreachable rooms (including key/flag closure), and any reachable puzzle state unable to reach both the goal and entrance. Its finite-state search uses the production engine with patrols omitted for logical puzzle solvability; separately test the live patrol timing and ledger replay. Do not confuse a static validator with a human playtest or a simulator run.

Before authoring wings 2–3, conduct a human playtest on iPhone after the issue-4 UI exists: start with no map, record whether players infer the false crypt return and the key/bell chain from authored clues, note stuck states and patrol-related deaths separately, check VoiceOver and one-thumb reach, then revise unfair clue text or timing **as a versioned content change**. This playtest has not occurred and is not claimed as evidence for this content milestone.
