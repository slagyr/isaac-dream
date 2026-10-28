(ns isaac.dream.habits-spec
  (:require
    [isaac.dream.habits :as sut]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(describe "Crew habits"
  (with fs* (fs/mem-fs))
  (with root "/dream-test")

  (it "stores a proposed lesson with its evidence under its crew"
    (let [habit (sut/propose! @fs* @root "hieronymus" "Water the moonflowers." ["greenhouse"] :manual)]
      (should= :proposed (:state habit))
      (should= ["greenhouse"] (:evidence (first (sut/list-habits @fs* @root "hieronymus"))))
      (should= [] (sut/list-habits @fs* @root "ketch"))))

  (it "automatically activates only when the crew opts in"
    (should= :active (:state (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :auto))))

  (it "rejects a proposal without evidence"
    (should-throw clojure.lang.ExceptionInfo
      (sut/propose! @fs* @root "ketch" "Keep watch." [] :manual))
    (should= [] (sut/list-habits @fs* @root "ketch")))

  (it "allows the operator to change a habit's state"
    (let [id (:id (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :manual))]
      (should= :active (:state (sut/change-state! @fs* @root "ketch" id :active)))
      (should= :retired (:state (sut/change-state! @fs* @root "ketch" id :retired)))))

  (it "wipes only the named crew"
    (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :manual)
    (sut/propose! @fs* @root "hieronymus" "Water first." ["greenhouse"] :manual)
    (sut/wipe! @fs* @root "ketch")
    (should= [] (sut/list-habits @fs* @root "ketch"))
    (should= 1 (count (sut/list-habits @fs* @root "hieronymus"))))

  (it "renders active lessons from operator-seeded EDN files"
    (fs/mkdirs @fs* "/dream-test/dream/ketch")
    (fs/spit @fs* "/dream-test/dream/ketch/geode.edn"
             "{:state \"active\" :lesson \"Look after the geode.\" :evidence [\"deck\"]}")
    (should= "These are lessons this crew learned\nLook after the geode."
             (:text (sut/section {:fs @fs* :root @root :crew "ketch"}))))

  (it "renders active lessons for only the current crew"
    (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :auto)
    (sut/propose! @fs* @root "ketch" "Check the ropes." ["deck"] :manual)
    (sut/propose! @fs* @root "hieronymus" "Water first." ["greenhouse"] :auto)
    (should= "These are lessons this crew learned\nKeep watch."
             (:text (sut/section {:fs @fs* :root @root :crew "ketch"})))))
