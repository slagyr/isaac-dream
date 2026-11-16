@wip
Feature: Dreams retire habits that people keep complaining about or that fade
  After a dream records what it found, it checks the crew's active habits:

  - Contradicted on two different UTC days: the dream retires the habit
    itself and the digest says so, with the command to bring it back.
    Complaints on the same day count once.
  - Strength (see features/habits/strength.feature) below
    dream.strength.floor (default 0.5): the digest proposes retiring it.
    A habit is proposed once; it is proposed again only after something
    reinforces or re-approves it and it fades again.
  - Pinned habits are never retired or proposed for retirement.

  Approving a retired habit makes it active again.

  Tracked by isaac-tpa5.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/isaac.edn" exists with:
      | path                    | value       |
      | attention.notify.comm   | discord     |
      | attention.notify.target | boiler-room |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value                                    |
      | model         | grover                                   |
      | soul          | You are Hieronymus, the ship's botanist. |
      | dream.enabled | true                                     |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And the clock is fixed at "2026-04-22T03:00:00Z"

  Scenario: complaints on two different days retire a habit and the digest says how to restore it
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                      |
      | state    | active                                                                                                                                                                                                     |
      | lesson   | Water the moonflowers first.                                                                                                                                                                               |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                                                                                                                                                               |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-10T03:00:00Z" :event :contradicted :by {:dream "2026-04-10T03:00:00Z"} :evidence [{:session "potting-shed" :entries ["e-2"]}]}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                 |
      | 2026-04-21T14:00:00Z | user         | Again with the moonflowers first? Ferns, please. |
    And the following model responses are queued:
      | type | content                                                           | model |
      | text | {"contradict":[{"id":"moonflowers","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value   |
      | id                | moonflowers |
      | state             | retired |
      | history[-1].event | retired |
      | history[-1].reason | contradicted |
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                               |
      | target  | boiler-room                                                                         |
      | content | contains "moonflowers" and "retired" and "dream approve moonflowers --crew hieronymus" |
    When isaac is run with "dream approve moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value       |
      | id                | moonflowers |
      | state             | active      |
      | history[-1].event | approved    |

  Scenario: complaints on the same day count once
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                      |
      | state    | active                                                                                                                                                                                                     |
      | lesson   | Water the moonflowers first.                                                                                                                                                                               |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                                                                                                                                                               |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-22T01:00:00Z" :event :contradicted :by {:dream "2026-04-22T01:00:00Z"} :evidence [{:session "potting-shed" :entries ["e-2"]}]}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                 |
      | 2026-04-22T02:00:00Z | user         | Again with the moonflowers first? Ferns, please. |
    And the following model responses are queued:
      | type | content                                                           | model |
      | text | {"contradict":[{"id":"moonflowers","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value        | #comment                    |
      | id                | moonflowers  |                             |
      | state             | active       | both complaints on 04-22    |
      | history[-1].event | contradicted |                             |

  Scenario: a habit that faded below the floor is proposed for retirement
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    |
      | model                         | grover                                   |
      | soul                          | You are Hieronymus, the ship's botanist. |
      | dream.enabled                 | true                                     |
      | dream.strength.half-life-days | 1                                        |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Water the moonflowers first.                                  |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                  |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content          |
      | 2026-04-05T14:00:00Z | user         | The ferns look thirsty.  |
      | 2026-04-06T14:00:00Z | user         | Orpheus dug up the mint. |
      | 2026-04-07T14:00:00Z | user         | Seed order arrived.      |
      | 2026-04-21T14:00:00Z | user         | Frost tonight, maybe.    |
    And the following model responses are queued:
      | type | content                       | model |
      | text | {"propose":[],"reinforce":[]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value          | #comment                           |
      | id                | moonflowers    |                                    |
      | state             | active         | the operator decides               |
      | history[-1].event | retire-proposed | 2 points behind four active days |
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                  |
      | content | contains "moonflowers" and "dream retire moonflowers --crew hieronymus" |

  Scenario: a faded habit already proposed for retirement is not proposed again
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    |
      | model                         | grover                                   |
      | soul                          | You are Hieronymus, the ship's botanist. |
      | dream.enabled                 | true                                     |
      | dream.strength.half-life-days | 1                                        |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                         |
      | state    | active                                                                                                                        |
      | lesson   | Water the moonflowers first.                                                                                                  |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                                                                                  |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-08T03:00:00Z" :event :retire-proposed :by {:dream "2026-04-08T03:00:00Z"}}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content          |
      | 2026-04-05T14:00:00Z | user         | The ferns look thirsty.  |
      | 2026-04-06T14:00:00Z | user         | Orpheus dug up the mint. |
      | 2026-04-07T14:00:00Z | user         | Seed order arrived.      |
      | 2026-04-21T14:00:00Z | user         | Frost tonight, maybe.    |
    And the following model responses are queued:
      | type | content                       | model |
      | text | {"propose":[],"reinforce":[]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And the directory "comm/delivery/pending" has exactly 0 files

  Scenario: a pinned habit is never proposed for retirement
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    |
      | model                         | grover                                   |
      | soul                          | You are Hieronymus, the ship's botanist. |
      | dream.enabled                 | true                                     |
      | dream.strength.half-life-days | 1                                        |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                   |
      | state    | active                                                                                                                  |
      | lesson   | Water the moonflowers first.                                                                                            |
      | pinned   | true                                                                                                                    |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                                                                            |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-01T00:00:00Z" :event :pinned :by :operator}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content          |
      | 2026-04-05T14:00:00Z | user         | The ferns look thirsty.  |
      | 2026-04-06T14:00:00Z | user         | Orpheus dug up the mint. |
      | 2026-04-07T14:00:00Z | user         | Seed order arrived.      |
      | 2026-04-21T14:00:00Z | user         | Frost tonight, maybe.    |
    And the following model responses are queued:
      | type | content                       | model |
      | text | {"propose":[],"reinforce":[]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And the directory "comm/delivery/pending" has exactly 0 files
    And crew "hieronymus" has a habit matching:
      | path              | value       |
      | id                | moonflowers |
      | state             | active      |
      | history[-1].event | pinned      |
