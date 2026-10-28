Feature: dream__propose stores habits as proposed
  A crew proposes a habit from a turn. The record is stored as proposed.
  Only the operator (or an :auto policy) can make it active. Evidence is
  required: the sessions the lesson came from.

  Tracked by isaac-b1ir.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | grover                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |

  Scenario: dream__propose stores a habit as proposed
    Given the crew "hieronymus" allows tools: dream/propose
    And the following model responses are queued:
      | type      | tool_call      | arguments                                                              | content | model |
      | tool_call | dream__propose | {"lesson":"Water the moonflowers first.","evidence":["greenhouse"]} |         | echo  |
      | text      |                |                                                                        | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then crew "hieronymus" has a habit matching:
      | path     | value                        |
      | state    | proposed                     |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |

  Scenario: dream__propose without evidence is refused
    Given the crew "hieronymus" allows tools: dream/propose
    And the following model responses are queued:
      | type      | tool_call      | arguments                                 | content | model |
      | tool_call | dream__propose | {"lesson":"Water the moonflowers first."} |         | echo  |
      | text      |                |                                           | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then session "greenhouse" has transcript matching:
      | type    | message.role | message.isError | message.content     |
      | message | toolResult   | true            | #"(?i).*evidence.*" |
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout does not contain "Water the moonflowers first."

  Scenario: dream__propose is refused when the crew has no grant
    Given the following model responses are queued:
      | type | content | model |
      | text | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then the prompt does not have tools:
      | name           |
      | dream__propose |

  Scenario: with per-crew dream.approval :auto, a valid propose becomes active
    Given the crew "hieronymus" allows tools: dream/propose
    And config:
      | dream.hieronymus.approval | :auto |
    And the following model responses are queued:
      | type      | tool_call      | arguments                                                              | content | model |
      | tool_call | dream__propose | {"lesson":"Water the moonflowers first.","evidence":["greenhouse"]} |         | echo  |
      | text      |                |                                                                        | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then crew "hieronymus" has a habit matching:
      | path     | value                        |
      | state    | active                       |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
