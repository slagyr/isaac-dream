Feature: Dreaming with an OAuth subscription
  A dream uses the same stored login as a crew turn when its model belongs to
  an OAuth provider. The login is kept under the Isaac root, not the project.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value                                    |
      | model         | nocturne                                 |
      | soul          | You are Hieronymus, the ship's botanist. |
      | dream.enabled | true                                     |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#1"]}]} | echo  |

  Scenario: a stored OAuth login lets a crew dream on grok
    Given the isaac EDN file "config/models/nocturne.edn" exists with:
      | path     | value         |
      | model    | nocturne      |
      | provider | grok          |
    And the isaac EDN file "config/providers/grok.edn" exists with:
      | path | value     |
      | type | :grok |
    And a stored OAuth login for "grok" with access token "at-moonflowers"
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path   | value                        |
      | state  | proposed                     |
      | lesson | Water the moonflowers first. |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path   | value     |
      | status | succeeded |
    And the dream provider request carries access token "at-moonflowers"

  Scenario: a stored OAuth login lets a crew dream on chatgpt
    Given the isaac EDN file "config/models/nocturne.edn" exists with:
      | path     | value         |
      | model    | nocturne      |
      | provider | chatgpt       |
    And the isaac EDN file "config/providers/chatgpt.edn" exists with:
      | path | value     |
      | type | :chatgpt |
    And a stored OAuth login for "chatgpt" with access token "at-moonflowers"
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path   | value                        |
      | state  | proposed                     |
      | lesson | Water the moonflowers first. |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path   | value     |
      | status | succeeded |
    And the dream provider request carries access token "at-moonflowers"

