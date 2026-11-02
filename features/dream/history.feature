Feature: Dreaming over history
  An operator can point one dream at any span of a crew's history with
  --since and --until (a date means midnight UTC). A window bigger than one
  model call is read in batches of dream.batch messages (default 400), one
  call each, until the window is done. The watermark moves to the end of what
  was read and never backward.

  Tracked by isaac-ff2r.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | grover                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |

  @wip
  Scenario: --since replays history from before the watermark
    Given the isaac EDN file "dream/hieronymus/state.edn" exists with:
      | path      | value                |
      | watermark | 2026-04-21T00:00:00Z |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-20T09:00:00Z | user         | Orpheus is sulking under the porch. |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content        | model |
      | text | {"propose":[]} | echo  |
    And the clock is fixed at "2026-04-22T03:00:00Z"
    When isaac is run with "dream run --crew hieronymus --since 2026-04-01"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                                  |
      | messages[-1].content | #"(?s).*Orpheus.*moonflowers first.*" |
    And the isaac file "dream/hieronymus/state.edn" EDN contains:
      | path      | value                |
      | watermark | 2026-04-22T03:00:00Z |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path         | value                |
      | window.since | 2026-04-01T00:00:00Z |
      | window.until | 2026-04-22T03:00:00Z |

  @wip
  Scenario: --until ends the window and the watermark there
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-20T09:00:00Z | user         | Orpheus is sulking under the porch. |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    And the following model responses are queued:
      | type | content        | model |
      | text | {"propose":[]} | echo  |
    And the clock is fixed at "2026-04-22T03:00:00Z"
    When isaac is run with "dream run --crew hieronymus --since 2026-04-01 --until 2026-04-21"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                |
      | messages[-1].content | #"(?s).*Orpheus.*" |
    And the last LLM request does not contain "moonflowers first"
    And the isaac file "dream/hieronymus/state.edn" EDN contains:
      | path      | value                |
      | watermark | 2026-04-21T00:00:00Z |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path         | value                |
      | window.until | 2026-04-21T00:00:00Z |

  @wip
  Scenario: replaying older history leaves a later watermark alone
    Given the isaac EDN file "dream/hieronymus/state.edn" exists with:
      | path      | value                |
      | watermark | 2026-04-22T00:00:00Z |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-20T09:00:00Z | user         | Orpheus is sulking under the porch. |
    And the following model responses are queued:
      | type | content        | model |
      | text | {"propose":[]} | echo  |
    And the clock is fixed at "2026-04-22T03:00:00Z"
    When isaac is run with "dream run --crew hieronymus --since 2026-04-01 --until 2026-04-21"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                |
      | messages[-1].content | #"(?s).*Orpheus.*" |
    And the isaac file "dream/hieronymus/state.edn" EDN contains:
      | path      | value                | #comment          |
      | watermark | 2026-04-22T00:00:00Z | never moves back |

  @wip
  Scenario: a large window is read in batches, one model call each
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path        | value |
      | dream.batch | 2     |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Orpheus is sulking under the porch. |
      | 2026-04-21T14:01:00Z | user         | Always water the moonflowers first. |
      | 2026-04-21T14:02:00Z | user         | Moonflowers before the ferns.       |
    And the following model responses are queued:
      | type | content                                                                                                | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#2"]}]} | echo  |
      | text | {"reinforce":[{"id":"moonflowers","evidence":["greenhouse#3"]}]}                                       | echo  |
    And the clock is fixed at "2026-04-22T03:00:00Z"
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And LLM request 1 matches:
      | key                  | value                                                 |
      | messages[-1].content | #"(?s)^(?!.*before the ferns).*Orpheus.*moonflowers first.*" |
    And LLM request 2 matches:
      | key                  | value                                                                       | #comment                                       |
      | messages[-1].content | #"(?s)^(?!.*Orpheus).*Water the moonflowers first\..*greenhouse#3 .*before the ferns.*" | sees the habit batch 1 proposed; labels go on |
    And crew "hieronymus" has a habit matching:
      | path                            | value       | #comment                                 |
      | id                              | moonflowers |                                          |
      | state                           | proposed    | reinforcing a proposed habit keeps state |
      | history[-1].event               | reinforced  |                                          |
      | history[-1].evidence[0].session | greenhouse  |                                          |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path        | value           |
      | status      | succeeded       |
      | batches     | 2               |
      | proposed    | ["moonflowers"] |
      | reinforced  | ["moonflowers"] |
    And the isaac file "dream/hieronymus/state.edn" EDN contains:
      | path      | value                |
      | watermark | 2026-04-22T03:00:00Z |

  @wip
  Scenario: a failed batch keeps what earlier batches found and the watermark where they stopped
    Given the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path        | value |
      | dream.batch | 2     |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Orpheus is sulking under the porch. |
      | 2026-04-21T14:01:00Z | user         | Always water the moonflowers first. |
      | 2026-04-21T14:02:00Z | user         | Moonflowers before the ferns.       |
    And the following model responses are queued:
      | type       | content                                                                                                | status | model |
      | text       | {"propose":[{"id":"moonflowers","lesson":"Water the moonflowers first.","evidence":["greenhouse#2"]}]} |        | echo  |
      | http-error |                                                                                                        | 500    | echo  |
    And the clock is fixed at "2026-04-22T03:00:00Z"
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 1
    And crew "hieronymus" has a habit matching:
      | path  | value       |
      | id    | moonflowers |
      | state | proposed    |
    And the isaac file "dream/hieronymus/state.edn" EDN contains:
      | path      | value                | #comment                       |
      | watermark | 2026-04-21T14:01:00Z | last message batch 1 read      |
      | lock      |                      | released for the next dream    |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path     | value           |
      | status   | failed          |
      | batches  | 1               |
      | proposed | ["moonflowers"] |
      | error    | #".*500.*"      |

  @wip
  Scenario: an unreadable --since is refused before any model call
    Given session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                     |
      | 2026-04-21T14:00:00Z | user         | Always water the moonflowers first. |
    When isaac is run with "dream run --crew hieronymus --since yesterday"
    Then the exit code is 1
    And the stderr contains "invalid --since: yesterday"
    And grover records zero provider requests
