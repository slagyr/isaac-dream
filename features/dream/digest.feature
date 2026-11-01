Feature: Dream digest
  After a dream, the operator gets one short message when there is
  something to act on: new proposals, or a failed dream. A quiet dream
  writes its diary entry and sends nothing. The digest goes to
  crew.<id>.dream.digest ({:comm … :to …}) if set, else the attention
  notify target.

  Tracked by isaac-p36b.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/isaac.edn" exists with:
      | path                    | value       |
      | attention.notify.comm   | discord     |
      | attention.notify.target | boiler-room |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value  |
      | model         | grover |
      | dream.enabled | true   |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the clock is fixed at "2026-04-22T03:00:00Z"

  Scenario: a dream with proposals sends one digest to the notify target
    Given the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the directory "comm/delivery/pending" has exactly 1 file
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                                                      |
      | comm    | :discord                                                                                                   |
      | target  | boiler-room                                                                                                |
      | content | contains "hieronymus" and "Water the moonflowers first." and "dream approve moonflowers --crew hieronymus" |

  Scenario: a dream that finds nothing sends no digest
    Given the following model responses are queued:
      | type | content        | model |
      | text | {"propose":[]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the directory "comm/delivery/pending" has exactly 0 files
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path   | value     |
      | status | succeeded |

  Scenario: a failed dream sends a failure digest
    Given the following model responses are queued:
      | type       | status | model |
      | http-error | 500    | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                              |
      | target  | boiler-room                        |
      | content | contains "hieronymus" and "failed" |

  Scenario: a crew's dream.digest overrides the notify target
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path              | value          |
      | dream.digest.comm | discord        |
      | dream.digest.to   | greenhouse-log |
    And the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the newest file in "comm/delivery/pending" EDN contains:
      | path   | value          |
      | comm   | :discord       |
      | target | greenhouse-log |
