Feature: Dream diary
  Every dream, quiet or not, writes one diary entry under
  dream/<crew>/diary/. The operator reads recent dreams with
  isaac dream diary.

  Tracked by isaac-p36b.

  Scenario: isaac dream diary shows recent dreams, newest first
    Given default Grover setup
    And the isaac EDN file "config/crew/hieronymus.edn" exists with:
      | path  | value  |
      | model | grover |
    And the isaac EDN file "dream/hieronymus/diary/2026-04-21T03-00-00Z.edn" exists with:
      | path     | value                                                         |
      | at       | 2026-04-21T03:00:00Z                                          |
      | status   | succeeded                                                     |
      | window   | {:since "2026-04-20T03:00:00Z" :until "2026-04-21T03:00:00Z"} |
      | sessions | ["greenhouse"]                                                |
      | proposed | []                                                            |
    And the isaac EDN file "dream/hieronymus/diary/2026-04-22T03-00-00Z.edn" exists with:
      | path     | value                                                         |
      | at       | 2026-04-22T03:00:00Z                                          |
      | status   | succeeded                                                     |
      | window   | {:since "2026-04-21T03:00:00Z" :until "2026-04-22T03:00:00Z"} |
      | sessions | ["greenhouse" "potting-shed"]                                 |
      | proposed | ["moonflowers"]                                               |
    When isaac is run with "dream diary --crew hieronymus"
    Then the exit code is 0
    And the stdout lines contain in order:
      | text                                                            |
      | 2026-04-22T03:00:00Z succeeded 2 sessions proposed: moonflowers |
      | 2026-04-21T03:00:00Z succeeded 1 session                        |
