Feature: Condensing habits into short rules as approvable revisions
  `isaac dream condense --crew <id>` sends the crew's active habits whose
  lesson is over 300 characters or that have no why to the model once. The
  model answers {"revise": [{"id", "lesson", "why"}]}. Each revision is
  stored on the habit as a pending :revision with a :revision-proposed
  event; the habit keeps its id, state, current lesson, evidence, history
  and strength until the operator decides, and the digest lists the
  revisions. `dream approve <id>` applies a pending revision (:revised
  event, the old lesson kept in it); `dream reject <id>` drops it and the
  habit stays as it was. Revision events carry no strength weight. A
  revised lesson over 300 characters is dropped.

  Tracked by isaac-pu21.

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

  Scenario: condense proposes short revisions for long habits and leaves them working
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                      |
      | state    | active                                                                                                                                                                                                                                                                                                                     |
      | lesson   | Water the moonflowers first. Two of them died in April after the ferns were watered first, and before that the gardener had been warned twice in March, once on a Tuesday and once on the Friday after the frost, that moonflowers wilt by noon when they wait in the sun while the ferns and the mint are watered first. |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                                 |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}]                                                                                                                                                                                                                                                              |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Deadhead the zinnias on Fridays, because they rebloom.        |
      | why      | The Friday deadheading doubled the July blooms.               |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    And the following model responses are queued:
      | type | content                                                                                                                                                                               | model |
      | text | {"revise":[{"id":"moonflowers","lesson":"Water the moonflowers first, because they wilt by noon.","why":"Two moonflowers died in April after the ferns were watered first."}]} | echo  |
    When isaac is run with "dream condense --crew hieronymus"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                                   | #comment                     |
      | messages[-1].content | #"(?s).*moonflowers.*wilt by noon.*"    | the long habit goes to the model |
    And the last LLM request does not contain "Deadhead the zinnias"
    And crew "hieronymus" has a habit matching:
      | path              | value                                                             | #comment                 |
      | id                | moonflowers                                                       |                          |
      | state             | active                                                            |                          |
      | lesson            | #"Water the moonflowers first\. Two of them died.*"               | still the working lesson |
      | revision.lesson   | Water the moonflowers first, because they wilt by noon.           |                          |
      | revision.why      | Two moonflowers died in April after the ferns were watered first. |                          |
      | history[-1].event | revision-proposed                                                 |                          |
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                                                   |
      | target  | boiler-room                                                                                             |
      | content | contains "moonflowers" and "because they wilt by noon" and "dream approve moonflowers --crew hieronymus" |

  Scenario: approving a revision applies it and keeps the habit's id, history and strength
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path                          | value                                    | #comment                                 |
      | model                         | grover                                   |                                          |
      | soul                          | You are Hieronymus, the ship's botanist. |                                          |
      | dream.enabled                 | true                                     |                                          |
      | dream.strength.half-life-days | 100000                                   | no decay, so the strength reads exactly |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                                                                                                                                                                                   |
      | state    | active                                                                                                                                                                                                                                                                                                                  |
      | lesson   | Water the moonflowers first. Two of them died in April after the ferns were watered first.                                                                                                                                                                                                                              |
      | revision | {:lesson "Water the moonflowers first, because they wilt by noon." :why "Two moonflowers died in April after the ferns were watered first."}                                                                                                                                                                           |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                                                                                                                                                                              |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-02T03:00:00Z" :event :reinforced :by {:dream "2026-04-02T03:00:00Z"} :evidence [{:session "greenhouse" :entries ["e-1"]}]} {:at "2026-04-03T00:00:00Z" :event :revision-proposed :by :condense}] |
    When isaac is run with "dream approve moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                 | value                                                                                      | #comment                   |
      | id                   | moonflowers                                                                                |                            |
      | state                | active                                                                                     |                            |
      | lesson               | Water the moonflowers first, because they wilt by noon.                                    |                            |
      | why                  | Two moonflowers died in April after the ferns were watered first.                          |                            |
      | revision             |                                                                                            | no longer pending          |
      | history[0].event     | approved                                                                                   | history kept               |
      | history[1].event     | reinforced                                                                                 |                            |
      | history[-1].event    | revised                                                                                    |                            |
      | history[-1].previous | Water the moonflowers first. Two of them died in April after the ferns were watered first. | the old wording is kept    |
    When isaac is run with "dream show moonflowers --crew hieronymus"
    Then the stdout matches:
      | pattern        | #comment                                   |
      | Strength: 3\.0 | approved 2 + reinforced 1; revising adds 0 |

  Scenario: rejecting a revision keeps the habit exactly as it was
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                                              |
      | state    | active                                                                                                                                                             |
      | lesson   | Water the moonflowers first. Two of them died in April after the ferns were watered first.                                                                         |
      | revision | {:lesson "Water the moonflowers first, because they wilt by noon." :why "Two moonflowers died in April after the ferns were watered first."}                      |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                                         |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-03T00:00:00Z" :event :revision-proposed :by :condense}]                                  |
    When isaac is run with "dream reject moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value                                                                                      | #comment                 |
      | state             | active                                                                                     | the habit is not rejected |
      | lesson            | Water the moonflowers first. Two of them died in April after the ferns were watered first. |                          |
      | revision          |                                                                                            |                          |
      | history[-1].event | revision-rejected                                                                          |                          |

  Scenario: a revised lesson over 300 characters is dropped
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Water the moonflowers first.                                  |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator}] |
    And the following model responses are queued:
      | type | content                                                                                                                                                                                                                                                                                                                                                                                                                                 | model |
      | text | {"revise":[{"id":"moonflowers","lesson":"Water the moonflowers first. Two of them died in April after the ferns were watered first, and before that the gardener had been warned twice in March, once on a Tuesday and once on the Friday after the frost, that moonflowers wilt by noon when they wait in the sun while the ferns, the mint and the zinnias are watered, so they must always be watered first.","why":"April."}]} | echo  |
    When isaac is run with "dream condense --crew hieronymus"
    Then the exit code is 0
    And the stdout contains "moonflowers"
    And the stdout contains "lesson-too-long"
    And crew "hieronymus" has a habit matching:
      | path              | value                        |
      | lesson            | Water the moonflowers first. |
      | revision          |                              |
      | history[-1].event | approved                     |
