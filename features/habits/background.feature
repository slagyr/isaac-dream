@wip
Feature: A habit is a short rule in the prompt, with its background on demand
  A habit's lesson is one short rule with its reason ("…, because …"), at
  most 300 characters, and it is the only part that goes in the system
  prompt. The story of how the habit formed lives in its why. With the
  evidence, the history and the strength, that is the habit's background.
  The operator reads it with `isaac dream show`; a crew reads its own with
  the dream__habit tool (grant dream/habit). A crew never reads another
  crew's habits.

  Tracked by isaac-4wsu.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value                                    |
      | model         | grover                                   |
      | soul          | You are Hieronymus, the ship's botanist. |
      | dream.enabled | true                                     |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And the clock is fixed at "2026-04-22T03:00:00Z"

  Scenario: a dream proposes a short rule and keeps the story in its why
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                       |
      | 2026-04-21T14:00:00Z | user         | We lost two moonflowers again. They have to go first. |
    And the following model responses are queued:
      | type | content                                                                                                                                                                                                         | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first, because they wilt by noon.","why":"Two moonflowers died in April after the ferns were watered first.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path   | value                                                             |
      | id     | moonflowers                                                       |
      | lesson | Water the moonflowers first, because they wilt by noon.           |
      | why    | Two moonflowers died in April after the ferns were watered first. |
    And the last LLM request matches:
      | key                  | value                  | #comment                          |
      | messages[-1].content | #"(?is).*one sentence.*" | the lesson is one short rule      |
      | messages[-1].content | #"(?is).*because.*"     | with its reason                   |
      | messages[-1].content | #"(?s).*\"why\".*"      | the story goes in its own field   |

  Scenario: a lesson longer than 300 characters is dropped and noted in the diary
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                       |
      | 2026-04-21T14:00:00Z | user         | We lost two moonflowers again. They have to go first. |
    And the following model responses are queued:
      | type | content                                                                                                                                                                                                                                                                                                                                                                                                                                  | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first. Two of them died in April after the ferns were watered first, and before that the gardener had already been warned twice in March, once on a Tuesday and once on the Friday after the frost, that moonflowers wilt by noon when they wait in the sun while the ferns, the mint and the zinnias are watered, so they must always, always be watered first.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path              | value           |
      | dropped[0].habit  | moonflowers     |
      | dropped[0].reason | lesson-too-long |
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout does not contain "moonflowers"

  Scenario: the system prompt carries the rule, never the why
    Given the isaac EDN file "config/models/claude.edn" exists with:
      | path           | value            |
      | model          | claude           |
      | provider       | grover:anthropic |
      | context-window | 200000           |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | claude                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                             |
      | state    | active                                                            |
      | lesson   | Water the moonflowers first, because they wilt by noon.           |
      | why      | Two moonflowers died in April after the ferns were watered first. |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                        |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :approved :by :operator}]     |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key            | value                                                                                  | #comment              |
      | system[0].text | #"(?s)\A(?!.*Two moonflowers died).*Water the moonflowers first, because they wilt by noon\..*" | rule in, story out |

  Scenario: dream show prints the rule, why, strength, quoted evidence and history
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                       |
      | 2026-04-21T14:00:00Z | user         | We lost two moonflowers again. They have to go first. |
    And the following model responses are queued:
      | type | content                                                                                                                                                                                                         | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first, because they wilt by noon.","why":"Two moonflowers died in April after the ferns were watered first.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    And isaac is run with "dream approve moonflowers --crew hieronymus"
    And isaac is run with "dream show moonflowers --crew hieronymus"
    Then the exit code is 0
    And the stdout matches:
      | pattern                                                                     |
      | Rule: Water the moonflowers first, because they wilt by noon\.              |
      | Why: Two moonflowers died in April after the ferns were watered first\.     |
      | Strength: 2\.0                                                              |
      | greenhouse .*2026-04-21T14:00:00Z user: We lost two moonflowers again\.     |
      | (?s)proposed.*approved                                                      |

  Scenario: dream__habit shows one habit's background to its own crew
    Given the crew "hieronymus" allows tools: dream/habit
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                       |
      | 2026-04-21T14:00:00Z | user         | We lost two moonflowers again. They have to go first. |
    And the following model responses are queued:
      | type      | tool_call    | arguments                                                                                                                                                                                                      | content | model |
      | text      |              |                                                                                                                                                                                                                | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first, because they wilt by noon.","why":"Two moonflowers died in April after the ferns were watered first.","evidence":["greenhouse#1"]}]} | echo  |
      | tool_call | dream__habit | {"id":"moonflowers"}                                                                                                                                                                                           |         | echo  |
      | text      |              |                                                                                                                                                                                                                | Noted.  | echo  |
    When isaac is run with "dream run --crew hieronymus"
    And isaac is run with "dream approve moonflowers --crew hieronymus"
    And the user sends "Why do the moonflowers go first?" on session "greenhouse"
    Then session "greenhouse" has transcript matching:
      | type    | message.role | message.content                                                                                       |
      | message | toolResult   | #"(?s).*Two moonflowers died in April.*[Ss]trength.*We lost two moonflowers again.*approved.*" |

  Scenario: dream__habit with no id lists the crew's habits with strength and pin
    Given the crew "hieronymus" allows tools: dream/habit
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                   |
      | state    | active                                                                                                                  |
      | lesson   | Water the moonflowers first, because they wilt by noon.                                                                 |
      | pinned   | true                                                                                                                    |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                              |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :approved :by :operator} {:at "2026-04-15T03:00:00Z" :event :pinned :by :operator}] |
    And the isaac EDN file "dream/hieronymus/zinnias.edn" exists with:
      | path     | value                                                         |
      | state    | proposed                                                      |
      | lesson   | Deadhead the zinnias on Fridays, because they rebloom.        |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}]                    |
      | history  | [{:at "2026-04-16T03:00:00Z" :event :proposed :by :crew}]     |
    And the following model responses are queued:
      | type      | tool_call    | arguments | content | model |
      | tool_call | dream__habit | {}        |         | echo  |
      | text      |              |           | Noted.  | echo  |
    When the user sends "What habits do you have?" on session "greenhouse"
    Then session "greenhouse" has transcript matching:
      | type    | message.role | message.content                                                                 |
      | message | toolResult   | #"(?s).*moonflowers.*active.*[Ss]trength.*pinned.*zinnias.*proposed.*"          |

  Scenario: dream__habit never reads another crew's habit
    Given the crew "hieronymus" allows tools: dream/habit
    And the isaac EDN file "dream/ketch/geode.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | The geode is in the attic, because Ketch hid it there.        |
      | evidence | [{:session "ketch-chat" :entries ["e-1"]}]                    |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :approved :by :operator}] |
    And the following model responses are queued:
      | type      | tool_call    | arguments      | content | model |
      | tool_call | dream__habit | {"id":"geode"} |         | echo  |
      | text      |              |                | Noted.  | echo  |
    When the user sends "Where is the geode?" on session "greenhouse"
    Then session "greenhouse" has transcript matching:
      | type    | message.role | message.content          |
      | message | toolResult   | #"(?is).*not found.*"    |
    And the last LLM request does not contain "The geode is in the attic"
