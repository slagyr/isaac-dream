Feature: Dream schedule
  Dreaming is off by default. A crew dreams only when its resolved
  dream.enabled is true, on its dream.schedule: a 5-field cron expression
  in the configured time zone, run on the shared scheduler. Shared
  settings live in defaults.crew.dream. Config changes reschedule without
  a restart.

  Tracked by isaac-p36b.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/isaac.edn" exists with:
      | path                         | value           |
      | tz                           | America/Chicago |
      | defaults.crew.dream.schedule | 0 3 * * *       |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value  |
      | model         | grover |
      | dream.enabled | true   |
    And the isaac EDN file "config/crew/ketch.edn" exists with:
      | path  | value  |
      | model | grover |

  Scenario: only enabled crews get a dream task
    Given the scheduler is started with the clock at "2026-04-22T12:00:00Z"
    When the dream service is started
    Then the scheduled tasks include:
      | id               | trigger.kind | trigger.expr | trigger.zone    |
      | dream/hieronymus | cron         | 0 3 * * *    | America/Chicago |
    And the scheduled tasks do not include "dream/ketch"

  Scenario: a scheduled dream fires at its local time and dreams
    Given the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#1"]}]} | echo  |
    And the scheduler is started with the clock at "2026-04-22T07:59:00Z"
    When the dream service is started
    And the clock advances "1m" and pending handlers complete
    Then crew "hieronymus" has a habit matching:
      | path  | value       | #comment                         |
      | id    | moonflowers |                                  |
      | state | proposed    | 03:00 Chicago (CDT) is 08:00 UTC |

  Scenario: an enabled crew with no schedule fails config validation
    Given the isaac EDN file "config/isaac.edn" exists with:
      | path                         | value   |
      | defaults.crew.dream.schedule | #delete |
    When isaac is run with "config validate"
    Then the exit code is 1
    And the stderr matches:
      | pattern                              |
      | crew\.hieronymus\.dream\.schedule    |
      | required when dream\.enabled is true |
      | file: config/crew/hieronymus\.edn    |
    And the stderr does not contain "ketch"

  Scenario: dream tasks follow config changes without a restart
    Given the scheduler is started with the clock at "2026-04-22T12:00:00Z"
    And the dream service is started
    When the isaac EDN file "config/crew/ketch.edn" exists with:
      | path           | value     |
      | dream.enabled  | true      |
      | dream.schedule | 0 * * * * |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value |
      | dream.enabled | false |
    And the config is reloaded
    Then the scheduled tasks include:
      | id          | trigger.kind | trigger.expr | trigger.zone    |
      | dream/ketch | cron         | 0 * * * *    | America/Chicago |
    And the scheduled tasks do not include "dream/hieronymus"

  @wip
  Scenario: a scheduled dream sends its digest
    Given the isaac EDN file "config/isaac.edn" exists with:
      | path                    | value       |
      | attention.notify.comm   | discord     |
      | attention.notify.target | boiler-room |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#1"]}]} | echo  |
    And the scheduler is started with the clock at "2026-04-22T07:59:00Z"
    When the dream service is started
    And the clock advances "1m" and pending handlers complete
    Then the directory "comm/delivery/pending" has exactly 1 file
    And the newest file in "comm/delivery/pending" EDN contains:
      | path    | value                                                                                                      |
      | comm    | :discord                                                                                                   |
      | target  | boiler-room                                                                                                |
      | content | contains "hieronymus" and "Water the moonflowers first." and "dream approve moonflowers --crew hieronymus" |

  @wip
  Scenario: a scheduled dream dreams on the crew's own model
    Given the isaac EDN file "config/models/nocturne.edn" exists with:
      | path     | value      |
      | model    | nocturne-7 |
      | provider | grover     |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value    | #comment                            |
      | model | nocturne | defaults.crew.model is still grover |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content        | model |
      | text | {"propose":[]} | echo  |
    And the scheduler is started with the clock at "2026-04-22T07:59:00Z"
    When the dream service is started
    And the clock advances "1m" and pending handlers complete
    Then the last LLM request matches:
      | key   | value      |
      | model | nocturne-7 |
