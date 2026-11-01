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
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
    And the isaac EDN file "dream/hieronymus/geode.edn" exists with:
      | path     | value                                      |
      | state    | active                                     |
      | lesson   | The geode is in the attic.                 |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
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
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
    When isaac is run with "dream approve moonflowers --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path   | value                        |
      | state  | active                       |
      | lesson | Water the moonflowers first. |

  Scenario: isaac dream reject keeps the habit out of the prompt
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                      |
      | state    | active                                     |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
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
      | path     | value                                      |
      | state    | active                                     |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
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
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
    And the isaac EDN file "dream/ketch/geode.edn" exists with:
      | path     | value                                      |
      | state    | active                                     |
      | lesson   | The geode is in the attic.                 |
      | evidence | [{:session "ketch-chat" :entries ["e-1"]}] |
    When isaac is run with "dream wipe --crew hieronymus"
    Then the exit code is 0
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout does not contain "moonflowers"
    When isaac is run with "dream list --crew ketch"
    Then the stdout contains "geode"

  Scenario: isaac dream list without --crew shows every crew's proposals
    Given the isaac EDN file "config/crew/ketch.edn" exists with:
      | path  | value  |
      | model | grover |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
    And the isaac EDN file "dream/hieronymus/geode.edn" exists with:
      | path     | value                                      |
      | state    | active                                     |
      | lesson   | The geode is in the attic.                 |
      | evidence | [{:session "greenhouse" :entries ["e-2"]}] |
    And the isaac EDN file "dream/ketch/rigging.edn" exists with:
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Check the rigging at dawn.                 |
      | evidence | [{:session "ketch-chat" :entries ["e-3"]}] |
    When isaac is run with "dream list --state proposed"
    Then the exit code is 0
    And the stdout matches:
      | pattern                                                                      |
      | hieronymus +moonflowers +proposed +Water the moonflowers first\. +greenhouse |
      | ketch +rigging +proposed +Check the rigging at dawn\. +ketch-chat            |
    And the stdout does not contain "geode"

  Scenario: approving with --lesson stores a reworded habit that supersedes the proposal
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                      |
      | state    | proposed                                   |
      | lesson   | Water the moonflowers first.               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}] |
    When isaac is run with "dream approve moonflowers --crew hieronymus --lesson \"Water the moonflowers before anything else.\""
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                | value                                       |
      | state               | active                                      |
      | lesson              | Water the moonflowers before anything else. |
      | supersedes[0]       | moonflowers                                 |
      | evidence[0].session | greenhouse                                  |
      | history[-1].by      | operator                                    |
    And crew "hieronymus" has a habit matching:
      | path          | value             |
      | id            | moonflowers       |
      | state         | retired           |
      | superseded-by | #"moonflowers-.+" |

  Scenario: an unknown crew is an error, not an empty list
    When isaac is run with "dream list --crew ghost"
    Then the exit code is 1
    And the stderr contains "unknown crew: ghost"
