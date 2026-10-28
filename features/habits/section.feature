Feature: Active always-on habits in the system prompt
  Approved always-on habits appear last in the cached system prefix,
  labelled as self-derived. Proposed habits and other crews' habits do not.

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

  Scenario: an active always-on habit appears last in the system prompt, labelled self-derived
    Given the isaac EDN file "config/models/claude.edn" exists with:
      | path           | value            |
      | model          | claude           |
      | provider       | grover:anthropic |
      | context-window | 200000           |
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value                                    |
      | model | claude                                   |
      | soul  | You are Hieronymus, the ship's botanist. |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | active                       |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    Then the prompt "Status?" on session "greenhouse" matches:
      | key                          | value                                                                                          | #comment                        |
      | system[0].text               | #"(?s).*ship's botanist.*These are lessons this crew learned.*Water the moonflowers first\." | soul, then labelled habits last |
      | system[0].cache_control.type | ephemeral                                                                                      | sits in the cached prefix       |

  Scenario: a proposed habit does not appear in the system prompt
    Given the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | proposed                     |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the following model responses are queued:
      | type | content | model |
      | text | Status. | echo  |
    When the user sends "Status?" on session "greenhouse"
    Then the system prompt does not contain "Water the moonflowers first."

  Scenario: another crew's system prompt does not contain this crew's habit
    Given the isaac EDN file "config/crew/ketch.edn" exists with:
      | path  | value          |
      | model | grover         |
      | soul  | You are Ketch. |
    And the following sessions exist:
      | name       | crew  |
      | ketch-chat | ketch |
    And the isaac EDN file "dream/hieronymus/moonflowers.edn" exists with:
      | path     | value                        |
      | state    | active                       |
      | lesson   | Water the moonflowers first. |
      | evidence | ["greenhouse"]               |
    And the following model responses are queued:
      | type | content | model |
      | text | Status. | echo  |
    When the user sends "Status?" on session "ketch-chat"
    Then the system prompt does not contain "Water the moonflowers first."
