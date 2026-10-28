@wip
Feature: Operator CLI for habits
  The operator lists, approves, rejects, retires, and wipes habits.
  The crew cannot do any of that. Only active habits reach the model.

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

  Scenario: isaac dream list shows a crew's habits by state
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | proposed                     |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the isaac EDN file "dream/hieronymus/geode.edn" exists with:
      | path     | value                      |
      | state    | active                     |
      | lesson   | The geode is in the attic. |
      | evidence | ["greenhouse"]             |
    When isaac is run with "dream list --crew hieronymus"
    Then the exit code is 0
    And the stdout matches:
      | pattern                      |
      | moonflowers                  |
      | proposed                     |
      | Water the moonflowers first. |
      | geode                        |
      | active                       |
      | The geode is in the attic.   |

  Scenario: isaac dream approve makes a proposed habit active
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | proposed                     |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    When isaac is run with "dream approve moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path   | value                        |
      | state  | active                       |
      | lesson | Water the moonflowers first. |

  Scenario: isaac dream reject keeps the habit out of the prompt
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | active                       |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the following model responses are queued:
      | type | content | model |
      | text | Status. | echo  |
    When isaac is run with "dream reject moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path  | value    |
      | state | rejected |
    When the user sends "Status?" on session "greenhouse"
    Then the system prompt does not contain "Water the moonflowers first."

  Scenario: isaac dream retire removes an active habit from the prompt
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | active                       |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the following model responses are queued:
      | type | content | model |
      | text | Status. | echo  |
    When isaac is run with "dream retire moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path  | value   |
      | state | retired |
    When the user sends "Status?" on session "greenhouse"
    Then the system prompt does not contain "Water the moonflowers first."

  Scenario: isaac dream wipe clears only that crew's habits
    Given the isaac EDN file "config/crew/ketch.edn" exists with:
      | path  | value          |
      | model | grover         |
      | soul  | You are Ketch. |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | proposed                     |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the isaac EDN file "dream/ketch/geode.edn" exists with:
      | path     | value                      |
      | state    | active                     |
      | lesson   | The geode is in the attic. |
      | evidence | ["ketch-chat"]             |
    When isaac is run with "dream wipe --crew hieronymus"
    Then the exit code is 0
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout does not contain "moonflowers"
    When isaac is run with "dream list --crew ketch"
    Then the stdout contains "geode"
