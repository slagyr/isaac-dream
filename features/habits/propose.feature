Feature: dream__propose stores habits as proposed
  A crew proposes a habit from a turn. The record is stored as proposed.
  Only the operator (or an :auto policy) can make it active. The tool
  attaches its own evidence: the calling session and the message that
  prompted it, so every habit traces back to its transcript.

  Tracked by isaac-b1ir; evidence shape and crew-level approval by isaac-p36b.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | grover                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |

  Scenario: dream__propose stores a habit as proposed, traced to the calling message
    Given the crew "hieronymus" allows tools: dream/propose
    And the following model responses are queued:
      | type      | tool_call      | arguments                                 | content | model |
      | tool_call | dream__propose | {"lesson":"Water the moonflowers first."} |         | echo  |
      | text      |                |                                           | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then crew "hieronymus" has a habit matching:
      | path                   | value                        |
      | state                  | proposed                     |
      | lesson                 | Water the moonflowers first. |
      | evidence[0].session    | greenhouse                   |
      | evidence[0].entries[0] | #".+"                        |
      | history[0].event       | proposed                     |
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout contains "Water the moonflowers first."

  Scenario: dream__propose is refused when the crew has no grant
    Given the following model responses are queued:
      | type | content | model |
      | text | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then the prompt does not have tools:
      | name           |
      | dream__propose |

  Scenario: with crew dream.approval :auto, a propose becomes active
    Given the crew "hieronymus" allows tools: dream/propose
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path           | value |
      | dream.approval | :auto |
    And the following model responses are queued:
      | type      | tool_call      | arguments                                 | content | model |
      | tool_call | dream__propose | {"lesson":"Water the moonflowers first."} |         | echo  |
      | text      |                |                                           | Noted.  | echo  |
    When the user sends "remember the moonflowers" on session "greenhouse"
    Then crew "hieronymus" has a habit matching:
      | path                | value                        |
      | state               | active                       |
      | lesson              | Water the moonflowers first. |
      | evidence[0].session | greenhouse                   |
      | history[1].by       | auto                         |
