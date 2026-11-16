(ns isaac.dream.habits-spec
  (:require
    [isaac.dream.habits :as sut]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.nexus :as nexus]
    [isaac.agent.session.store.memory :as memory-store]
    [isaac.agent.session.store.spi :as store]
    [isaac.agent.tool.memory :as memory]
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
             (:text (sut/section {:fs @fs* :root @root :crew "ketch"}))))  (it "retires superseded habits on approval without changing their lessons"
    (let [old (sut/propose! @fs* @root "ketch" "Keep watch." [{:session "deck" :entries ["e-1"]}] :auto)
          new (sut/propose! @fs* @root "ketch" "Watch the rigging." [{:session "deck" :entries ["e-2"]}] :manual)]
      (sut/change-state! @fs* @root "ketch" (:id new) :active)
      (should= :active (:state (first (filter #(= (:id old) (:id %)) (sut/list-habits @fs* @root "ketch")))))))

  (it "reinforces a proposed habit without approving it"
    (let [id (:id (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :manual))]
      (sut/reinforce! @fs* @root "ketch" id [{:session "deck" :entries ["e-2"]}] "2026-04-21T00:00:00Z")
      (let [habit (sut/find-habit @fs* @root "ketch" id)]
        (should= :proposed (:state habit))
        (should= :reinforced (:event (last (:history habit)))))))

  (it "records the approval event in an append-only history"
    (let [id (:id (sut/propose! @fs* @root "ketch" "Keep watch." [{:session "deck" :entries ["e-1"]}] :manual))]
      (sut/change-state! @fs* @root "ketch" id :active)
      (should= [:proposed :approved] (mapv :event (:history (first (sut/list-habits @fs* @root "ketch")))))))

  (it "counts each event kind once per UTC day and fades across crew active days"
    (let [history [{:at "2026-04-01T00:00:00Z" :event :approved}
                   {:at "2026-04-02T01:00:00Z" :event :reinforced}
                   {:at "2026-04-02T02:00:00Z" :event :reinforced :kind :taught}
                   {:at "2026-04-02T03:00:00Z" :event :reinforced :kind :applied}
                   {:at "2026-04-03T01:00:00Z" :event :contradicted}]
          days #{"2026-04-02" "2026-04-04"}]
      (should= -0.5 (sut/strength {:history history} days {:half-life-days 1}))))

  (it "pins a lesson without changing its strength"
    (let [id (:id (sut/propose! @fs* @root "ketch" "Keep watch." ["deck"] :auto))]
      (sut/pin! @fs* @root "ketch" id true)
      (should= true (:pinned (sut/find-habit @fs* @root "ketch" id)))
      (should= :pinned (:event (last (:history (sut/find-habit @fs* @root "ketch" id)))))))

  (it "reserves the budget for pinned lessons before stronger unpinned ones"
    (doseq [[id lesson history pinned] [["a" "A lesson." [{:at "2026-04-01T00:00:00Z" :event :approved}] true]
                                        ["b" "B longer lesson." [{:at "2026-04-01T00:00:00Z" :event :approved}
                                                                  {:at "2026-04-02T00:00:00Z" :event :reinforced}] false]]]
      (sut/save! @fs* @root "ketch" {:id id :state :active :lesson lesson :history history :pinned pinned}))
    (should= "These are lessons this crew learned\nA lesson."
             (:text (sut/section {:fs @fs* :root @root :crew "ketch" :config {:crew {"ketch" {:dream {:prompt-chars 12}}}}}))))

  (it "counts all crews' sessions once per UTC day, regardless of turn origin"
    (with-out-str (nexus/-with-nexus {:fs @fs*}
      (binding [memory/*now* (java.time.Instant/parse "2026-04-02T00:00:00Z")]
      (let [ss (memory-store/create-store "/dream-test")]
      (store/open-session! ss "deck" {:crew "ketch"})
      (store/open-session! ss "mast" {:crew "ketch"})
      (store/open-session! ss "garden" {:crew "hieronymus"})
      (with-redefs [isaac.agent.tool.memory/now (constantly (java.time.Instant/parse "2026-04-02T23:00:00Z"))]
        (store/append-message! ss "deck" {:role "user" :content "Ahoy"}))
      (with-redefs [isaac.agent.tool.memory/now (constantly (java.time.Instant/parse "2026-04-02T23:30:00Z"))]
        (store/append-message! ss "mast" {:role "assistant" :content "All clear"}))
      (with-redefs [isaac.agent.tool.memory/now (constantly (java.time.Instant/parse "2026-04-03T01:00:00Z"))]
        (store/append-message! ss "garden" {:role "user" :content "Water"}))
      (should= #{"2026-04-02"} (sut/active-days ss "ketch")))))))

  (it "weights are reconfigurable without modifying the saved history"
    (let [habit {:history [{:at "2026-04-01T00:00:00Z" :event :approved}
                           {:at "2026-04-02T00:00:00Z" :event :contradicted}]}]
      (should= -2.0 (sut/strength habit #{} {}))
      (should= 1.0 (sut/strength habit #{} {:approved 5 :contradicted -4}))))

)
