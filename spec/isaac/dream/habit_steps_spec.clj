(ns isaac.dream.habit-steps-spec
  (:require
    [gherclj.core :as g]
    [isaac.agent.session.session-steps :as session-steps]
    [isaac.dream.habit-steps :as sut]
    [isaac.dream.habits :as habits]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer [around describe it should=]]))

(describe "habit feature steps"
  (around [it]
    (g/reset!)
    (try (it) (finally (g/reset!))))

  (it "sees a moonflower habit written when the turn finishes"
    (let [fs* (fs/mem-fs)]
      (g/assoc! :mem-fs fs*)
      (g/assoc! :root "/dream-test")
      (with-redefs [session-steps/await-turn! #(habits/propose! fs* "/dream-test" "hieronymus"
                                                                "Water the moonflowers first."
                                                                ["greenhouse"] :manual)]
        (sut/crew-has-habit "hieronymus" {:headers ["lesson"]
                                            :rows [["Water the moonflowers first."]]})
        (should= 1 (count (habits/list-habits fs* "/dream-test" "hieronymus")))))))
