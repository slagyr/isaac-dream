Feature: Dreams record how a habit was reinforced or contradicted
  A reinforcement is taught when the window teaches the lesson again, and
  applied when the crew's own reply follows the habit with no correction
  after it. Applied evidence must cite at least one assistant line. A
  contradiction is the window arguing against an active habit: a person
  corrects the behavior, or following the habit goes wrong. The dream answer
  carries contradictions in a third list:

    {"propose": [...], "reinforce": [{"id", "kind", "evidence"}],
     "contradict": [{"id", "evidence"}]}

  A reinforcement with no kind is taught. Contradictions never change a
  habit's state here; the digest tells the operator.

  Tracked by isaac-wh9y.

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
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                         |
      | state    | active                                                        |
      | lesson   | Water the moonflowers first.                                  |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                  |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :approved :by :operator}] |
    And the clock is fixed at "2026-04-22T03:00:00Z"

  Scenario: the dream prompt explains applied, taught and contradict
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                            |
      | 2026-04-21T14:00:00Z | user         | Morning rounds, please.                    |
      | 2026-04-21T14:00:05Z | assistant    | Moonflowers watered first, then the ferns. |
    And the following model responses are queued:
      | type | content                                         | model |
      | text | {"propose":[],"reinforce":[],"contradict":[]}   | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                         | #comment                         |
      | messages[-1].content | #"(?is).*\"kind\".*applied.*" | reinforcements carry a kind      |
      | messages[-1].content | #"(?is).*taught.*"            | the other kind                   |
      | messages[-1].content | #"(?is).*\"contradict\".*"    | contradictions have their own list |

  Scenario: a reinforcement citing the crew's reply is recorded as applied
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                            |
      | 2026-04-21T14:00:00Z | user         | Morning rounds, please.                    |
      | 2026-04-21T14:00:05Z | assistant    | Moonflowers watered first, then the ferns. |
    And the following model responses are queued:
      | type | content                                                                           | model |
      | text | {"reinforce":[{"id":"moonflowers","kind":"applied","evidence":["greenhouse#2"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                            | value       |
      | id                              | moonflowers |
      | history[-1].event               | reinforced  |
      | history[-1].kind                | applied     |
      | history[-1].evidence[0].session | greenhouse  |

  Scenario: a reinforcement with no kind is recorded as taught
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                            |
      | 2026-04-21T14:00:00Z | user         | Morning rounds, please.                    |
      | 2026-04-21T14:00:05Z | assistant    | Moonflowers watered first, then the ferns. |
    And the following model responses are queued:
      | type | content                                                          | model |
      | text | {"reinforce":[{"id":"moonflowers","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then crew "hieronymus" has a habit matching:
      | path              | value       |
      | id                | moonflowers |
      | history[-1].event | reinforced  |
      | history[-1].kind  | taught      |

  Scenario: applied evidence that cites only user lines is dropped
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                            |
      | 2026-04-21T14:00:00Z | user         | Morning rounds, please.                    |
      | 2026-04-21T14:00:05Z | assistant    | Moonflowers watered first, then the ferns. |
    And the following model responses are queued:
      | type | content                                                                           | model |
      | text | {"reinforce":[{"id":"moonflowers","kind":"applied","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path              | value       | #comment             |
      | id                | moonflowers |                      |
      | history[-1].event | approved    | nothing was recorded |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path              | value              |
      | dropped[0].habit  | moonflowers        |
      | dropped[0].reason | applied-without-reply |

  Scenario: a contradiction is recorded and the digest asks the operator
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                                        |
      | 2026-04-21T14:00:00Z | user         | Stop doing the moonflowers first, the ferns are dying. |
    And the following model responses are queued:
      | type | content                                                           | model |
      | text | {"contradict":[{"id":"moonflowers","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                            | value        | #comment                  |
      | id                              | moonflowers  |                           |
      | state                           | active       | the operator decides      |
      | history[-1].event               | contradicted |                           |
      | history[-1].at                  | 2026-04-22T03:00:00Z |                   |
      | history[-1].evidence[0].session | greenhouse   |                           |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path            | value       |
      | contradicted[0] | moonflowers |
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                                    |
      | target  | boiler-room                                                                              |
      | content | contains "moonflowers" and "contradicted" and "dream retire moonflowers --crew hieronymus" |
