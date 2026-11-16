@wip
Feature: Habit strength orders the habits section
  Every habit has a strength computed from its history, never stored:

    approved            +2
    reinforced (taught) +1   a reinforcement with no :kind is taught
    reinforced (applied) +1
    contradicted        -4

  Each kind counts at most once per habit per UTC day, however many events
  that day holds. An event's weight halves for every
  dream.strength.half-life-days (default 30) active days after the day it
  happened. An active day is a UTC day on which any of the crew's sessions
  has a transcript entry, whoever started the turn. Days without activity
  never decay a habit.

  The habits section lists active habits strongest first, pinned habits
  ahead of all of them, and stops before the lesson that would take the
  lessons past dream.prompt-chars (default 6000) characters; only lesson
  text counts. Pinned habits are always listed and count toward the budget,
  so they take room before any unpinned habit.

  Tracked by isaac-o4di.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/models/claude.edn" exists with:
      | path           | value            |
      | model          | claude           |
      | provider       | grover:anthropic |
      | context-window | 200000           |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | claude                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |

  Scenario: the strongest habit comes first
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                |
      | state    | active                                                               |
      | lesson   | Water the moonflowers first.                                         |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                           |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}]        |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                         |
      | state    | active                                                                                                                                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                              |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-10T03:00:00Z" :event :reinforced :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-3"]}]}] |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                  | #comment                         |
      | system[0].text | #"(?s).*Deadhead the zinnias on Fridays\..*Water the moonflowers first\..*" | zinnias 3, moonflowers 2         |

  Scenario: habits decay over active days
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    |
      | model                         | claude                                   |
      | soul                          | You are Hieronymus, the ship's botanist. |
      | dream.strength.half-life-days | 1                                        |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                   |
      | state    | active                                                                                                                                                                                                                                                                                                                  |
      | lesson   | Water the moonflowers first.                                                                                                                                                                                                                                                                                            |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                              |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-02T03:00:00Z" :event :reinforced :by {:dream "2026-04-02T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-03T03:00:00Z" :event :reinforced :by {:dream "2026-04-03T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                         |
      | state    | active                                                                                                                                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                              |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-12T03:00:00Z" :event :reinforced :by {:dream "2026-04-12T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-2"]}]}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content          |
      | 2026-04-05T14:00:00Z | user         | The ferns look thirsty.  |
      | 2026-04-06T14:00:00Z | user         | Orpheus dug up the mint. |
      | 2026-04-07T14:00:00Z | user         | Seed order arrived.      |
      | 2026-04-08T14:00:00Z | user         | Frost tonight, maybe.    |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                  | #comment                                                   |
      | system[0].text | #"(?s).*Deadhead the zinnias on Fridays\..*Water the moonflowers first\..*" | moonflowers' 4 points sit behind four active days; zinnias' reinforcement is newer |

  Scenario: days with no activity do not decay habits
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    |
      | model                         | claude                                   |
      | soul                          | You are Hieronymus, the ship's botanist. |
      | dream.strength.half-life-days | 1                                        |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                   |
      | state    | active                                                                                                                                                                                                                                                                                                                  |
      | lesson   | Water the moonflowers first.                                                                                                                                                                                                                                                                                            |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                              |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-02T03:00:00Z" :event :reinforced :by {:dream "2026-04-02T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-03T03:00:00Z" :event :reinforced :by {:dream "2026-04-03T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                         |
      | state    | active                                                                                                                                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                              |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-12T03:00:00Z" :event :reinforced :by {:dream "2026-04-12T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-2"]}]}] |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                  | #comment                                  |
      | system[0].text | #"(?s).*Water the moonflowers first\..*Deadhead the zinnias on Fridays\..*" | no active days between: moonflowers 4, zinnias 3 |

  Scenario: a habit earns one reinforcement per day however often it comes up
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                                                                                                                            |
      | state    | active                                                                                                                                                                                                                                                                                                                                                                                                                           |
      | lesson   | Water the moonflowers first.                                                                                                                                                                                                                                                                                                                                                                                                     |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                                                                                                                                       |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-10T01:00:00Z" :event :reinforced :by {:dream "2026-04-10T01:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-10T02:00:00Z" :event :reinforced :by {:dream "2026-04-10T02:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-10T03:00:00Z" :event :reinforced :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                   |
      | state    | active                                                                                                                                                                                                                                                                                                                  |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                                                                                                                                                                        |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                                                                                                                                                              |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-09T03:00:00Z" :event :reinforced :by {:dream "2026-04-09T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-2"]}]} {:at "2026-04-10T03:00:00Z" :event :reinforced :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-2"]}]}] |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                  | #comment                                             |
      | system[0].text | #"(?s).*Deadhead the zinnias on Fridays\..*Water the moonflowers first\..*" | three reinforcements on 04-10 count once: 3 vs 4     |

  Scenario: a complaint costs far more than a reinforcement earns
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
      | state    | active                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
      | lesson   | Water the moonflowers first.                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-08T03:00:00Z" :event :reinforced :by {:dream "2026-04-08T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-09T03:00:00Z" :event :reinforced :kind :applied :by {:dream "2026-04-09T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-2"]}]} {:at "2026-04-11T03:00:00Z" :event :contradicted :by {:dream "2026-04-11T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-3"]}]}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                              |
      | evidence | [{:session "greenhouse" :entries ["e-4"]}]                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                  | #comment                          |
      | system[0].text | #"(?s).*Deadhead the zinnias on Fridays\..*Water the moonflowers first\..*" | moonflowers 2+1+1-4 = 0, zinnias 2 |

  Scenario: habits past the prompt budget stay active but leave the prompt
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path               | value                                    |
      | model              | claude                                   |
      | soul               | You are Hieronymus, the ship's botanist. |
      | dream.prompt-chars | 40                                       |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Water the moonflowers first.                                  |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                         |
      | state    | active                                                                                                                                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                              |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-10T03:00:00Z" :event :reinforced :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-3"]}]}] |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                        | #comment                         |
      | system[0].text | #"(?s)\A(?!.*Water the moonflowers first).*Deadhead the zinnias on Fridays\..*" | only the stronger habit fits 40  |
    And crew "hieronymus" has a habit matching:
      | path  | value       |
      | id    | moonflowers |
      | state | active      |

  Scenario: a pinned habit takes its place in the prompt ahead of stronger habits
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path               | value                                    |
      | model              | claude                                   |
      | soul               | You are Hieronymus, the ship's botanist. |
      | dream.prompt-chars | 40                                       |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Water the moonflowers first.                                  |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                                                                                                                                         |
      | state    | active                                                                                                                                                                        |
      | lesson   | Deadhead the zinnias on Fridays.                                                                                                                                              |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                                                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-10T03:00:00Z" :event :reinforced :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-3"]}]}] |
    When isaac is run with "dream pin moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value       |
      | id                | moonflowers |
      | pinned            | true        |
      | history[-1].event | pinned      |
    And the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                        | #comment                                         |
      | system[0].text | #"(?s)\A(?!.*Deadhead the zinnias).*Water the moonflowers first\..*"           | the pinned habit takes the room; zinnias is out  |

  Scenario: unpinning returns a habit to its strength
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                  |
      | state    | active                                                                                                                                 |
      | lesson   | Water the moonflowers first.                                                                                                           |
      | pinned   | true                                                                                                                                   |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                             |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-02T00:00:00Z" :event :pinned :by :operator}]                 |
    When isaac is run with "dream unpin moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value       |
      | id                | moonflowers |
      | pinned            | false       |
      | history[-1].event | unpinned    |

  Scenario: dream show prints a habit's strength and pin
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                  |
      | state    | active                                                                                                                                 |
      | lesson   | Water the moonflowers first.                                                                                                           |
      | pinned   | true                                                                                                                                   |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                             |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-02T00:00:00Z" :event :pinned :by :operator}]                 |
    When isaac is run with "dream show moonflowers --crew hieronymus"
    Then the exit code is 0
    And the stdout matches:
      | pattern        |
      | Strength: 2\.0 |
      | Pinned: yes    |
