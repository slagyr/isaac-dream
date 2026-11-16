Feature: Dreams build on existing habits instead of repeating them
  A dream sees every habit the crew already has, whatever its state. When the
  window repeats a lesson the crew already has, the dream reinforces that
  habit. When the window sharpens it, the dream proposes a new habit that
  supersedes it. Two active habits that say the same thing merge into one
  that supersedes both. Only a genuinely new lesson gets a new id.

  Tracked by isaac-gomk.

  Background:
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path          | value                                    |
      | model         | grover                                   |
      | soul          | You are Hieronymus, the ship's botanist. |
      | dream.enabled | true                                     |
    And the following sessions exist:
      | name       | crew       |
      | greenhouse | hieronymus |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                                                                               |
      | state    | proposed                                                                            |
      | lesson   | Water the moonflowers first.                                                        |
      | evidence | [{:session "potting-shed" :entries ["e-1"]}]                                        |
      | history  | [{:at "2026-04-15T03:00:00Z" :event :proposed :by {:dream "2026-04-15T03:00:00Z"}}] |
    And session "greenhouse" has transcript:
      | timestamp            | message.role | message.content                       |
      | 2026-04-21T14:00:00Z | user         | Moonflowers before the ferns, always. |
    And the clock is fixed at "2026-04-22T03:00:00Z"

  Scenario: the dream prompt asks the model to build on existing habits
    Given the following model responses are queued:
      | type | content                       | model |
      | text | {"propose":[],"reinforce":[]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And the last LLM request matches:
      | key                  | value                                                     | #comment                              |
      | messages[-1].content | #"(?s).*moonflowers proposed Water the moonflowers first.*" | existing habits, with their state     |
      | messages[-1].content | #"(?is).*same lesson.*reinforce.*"                        | a repeated lesson reinforces          |
      | messages[-1].content | #"(?is).*sharper.*supersedes.*"                           | a sharper lesson supersedes           |
      | messages[-1].content | #"(?is).*two active habits.*merge.*supersed.*"            | duplicate actives merge into one      |

  Scenario: a proposal that reuses an existing habit's id reinforces that habit
    Given the following model responses are queued:
      | type | content                                                                                                         | model |
      | text | {"propose":[{"id":"moonflowers","lesson":"Water moonflowers before the ferns.","evidence":["greenhouse#1"]}]} | echo  |
    When isaac is run with "dream run --crew hieronymus"
    Then the exit code is 0
    And crew "hieronymus" has a habit matching:
      | path                            | value                        | #comment               |
      | id                              | moonflowers                  |                        |
      | state                           | proposed                     |                        |
      | lesson                          | Water the moonflowers first. | the lesson is unchanged |
      | history[-1].event               | reinforced                   |                        |
      | history[-1].evidence[0].session | greenhouse                   |                        |
    And the newest file in "dream/hieronymus/diary" EDN contains:
      | path          | value       |
      | status        | succeeded   |
      | reinforced[0] | moonflowers |
