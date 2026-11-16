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

  Scenario: approving with --lesson rewords the habit in place
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                      |
      | state    | proposed                                                   |
      | lesson   | Water the moonflowers first.                               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                 |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :proposed :by :crew}]  |
    When isaac is run with "dream approve moonflowers --crew hieronymus --lesson \"Water the moonflowers before anything else, because they wilt by noon.\""
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                 | value                                                                  | #comment              |
      | id                   | moonflowers                                                            | same habit, same id   |
      | state                | active                                                                 |                       |
      | lesson               | Water the moonflowers before anything else, because they wilt by noon. |                       |
      | evidence[0].session  | greenhouse                                                             |                       |
      | history[0].event     | proposed                                                               | history kept          |
      | history[-1].event    | revised                                                                |                       |
      | history[-1].previous | Water the moonflowers first.                                           |                       |
    When isaac is run with "dream list --crew hieronymus"
    Then the stdout does not contain "moonflowers-"

  Scenario: approving a pending revision with --lesson keeps the revision's why
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                                                                                         |
      | state    | active                                                                                                                                        |
      | lesson   | Water the moonflowers first. Two of them died in April after the ferns were watered first.                                                    |
      | revision | {:lesson "Water the moonflowers first, because they wilt." :why "Two moonflowers died in April after the ferns were watered first."}          |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                                                                                                    |
      | history  | [{:at "2026-04-01T00:00:00Z" :event :approved :by :operator} {:at "2026-04-03T00:00:00Z" :event :revision-proposed :by :condense}]             |
    When isaac is run with "dream approve moonflowers --crew hieronymus --lesson \"Water the moonflowers before anything else, because they wilt by noon.\""
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                 | value                                                                                      |
      | id                   | moonflowers                                                                                |
      | lesson               | Water the moonflowers before anything else, because they wilt by noon.                     |
      | why                  | Two moonflowers died in April after the ferns were watered first.                          |
      | revision             |                                                                                            |
      | history[-1].event    | revised                                                                                    |
      | history[-1].previous | Water the moonflowers first. Two of them died in April after the ferns were watered first. |

  Scenario: a --lesson over 300 characters is refused and the habit is unchanged
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                      |
      | state    | proposed                                                   |
      | lesson   | Water the moonflowers first.                               |
      | evidence | [{:session "greenhouse" :entries ["e-1"]}]                 |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :proposed :by :crew}]  |
    When isaac is run with "dream approve moonflowers --crew hieronymus --lesson \"Water the moonflowers first. Two of them died in April after the ferns were watered first, and before that the gardener had been warned twice in March, once on a Tuesday and once on the Friday after the frost, that moonflowers wilt by noon when they wait in the sun while the ferns, the mint and the zinnias are watered first.\""
    Then the exit code is 1
    And the stderr contains "300"
    And crew "hieronymus" has a habit matching:
      | path              | value                        |
      | state             | proposed                     |
      | lesson            | Water the moonflowers first. |
      | history[-1].event | proposed                     |

  Scenario: an unknown crew is an error, not an empty list
    When isaac is run with "dream list --crew ghost"
    Then the exit code is 1
    And the stderr contains "unknown crew: ghost"
