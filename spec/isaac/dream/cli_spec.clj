(ns isaac.dream.cli-spec
  (:require
    [isaac.dream.cli :as sut]
    [isaac.dream.habits :as habits]
    [isaac.dream.run :as dream-run]
    [isaac.agent.config.resolve :as resolve]
    [isaac.agent.drive.dispatch :as dispatch]
    [isaac.agent.comm.delivery.queue :as delivery]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(describe "Operator habit commands"
  (with fs* (fs/mem-fs))
  (with opts {:root "/dream-test" :fs @fs* :config {:crew {"ketch" {:model "grover"}}}})
  (it "names the contradicted lesson and retire command in the digest"
    (let [sent (atom nil)]
      (habits/propose! @fs* "/dream-test" "ketch" "Watch the rigging."
                       [{:session "deck" :entries ["e-1"]}] :auto {:id "rigging"})
      (with-redefs [dream-run/run! (fn [{:keys [notify!]}]
                                    (notify! "ketch" [] nil ["rigging"])
                                    {:status "succeeded"})
                    delivery/enqueue! (fn [message] (reset! sent message))]
        (should= 0 (sut/run (assoc @opts :config {:crew {"ketch" {}}
                                              :attention {:notify {:comm "discord" :target "deck"}}}
                                  :_raw-args ["run" "--crew" "ketch"])))
        (should-contain "rigging: Watch the rigging. contradicted — dream retire rigging --crew ketch"
                        (:content @sent)))))
  (it "condenses only eligible active habits in one call and delivers pending revisions"
    (let [request (atom nil) sent (atom nil)]
      (doseq [[id lesson why state] [["moonflowers" (apply str (repeat 301 "m")) nil :active]
                                      ["zinnias" "Deadhead Fridays." "For more blooms." :active]
                                      ["mint" "Keep mint shaded." nil :retired]]]
        (habits/save! @fs* "/dream-test" "ketch" {:id id :state state :lesson lesson :why why
                                                     :history [{:at "2026-04-01T00:00:00Z" :event :approved}]}))
      (with-redefs [resolve/resolve-crew-context (fn [& _] {:provider :grover :model "echo" :soul "Botanist"})
                    dispatch/dispatch-chat (fn [_ message]
                                             (reset! request message)
                                             {:content "{\"revise\":[{\"id\":\"moonflowers\",\"lesson\":\"Water first, because they wilt.\",\"why\":\"April loss.\"}]}"})
                    delivery/enqueue! (fn [message] (reset! sent message))]
        (should= 0 (sut/run (assoc @opts :config {:crew {"ketch" {:model "grover"}}
                                                  :attention {:notify {:comm "discord" :target "deck"}}}
                                    :_raw-args ["condense" "--crew" "ketch"]))))
      (should-contain "moonflowers" (get-in @request [:messages 0 :content]))
      (should-not-contain "zinnias" (get-in @request [:messages 0 :content]))
      (should-not-contain "mint" (get-in @request [:messages 0 :content]))
      (should= "Water first, because they wilt." (get-in (habits/find-habit @fs* "/dream-test" "ketch" "moonflowers") [:revision :lesson]))
      (should-contain "dream approve moonflowers --crew ketch" (:content @sent))))

  (it "drops an oversized revision without modifying the habit"
    (habits/save! @fs* "/dream-test" "ketch" {:id "moonflowers" :state :active :lesson "Water first." :history []})
    (with-redefs [resolve/resolve-crew-context (fn [& _] {:provider :grover :model "echo" :soul "Botanist"})
                  dispatch/dispatch-chat (fn [& _] {:content (str "{\"revise\":[{\"id\":\"moonflowers\",\"lesson\":\""
                                                                 (apply str (repeat 301 "m")) "\",\"why\":\"April.\"}]}")})]
      (let [output (with-out-str (should= 0 (sut/run (assoc @opts :_raw-args ["condense" "--crew" "ketch"]))))]
        (should-contain "moonflowers lesson-too-long" output)))
    (should-be-nil (:revision (habits/find-habit @fs* "/dream-test" "ketch" "moonflowers"))))

  (it "parses dates at UTC midnight and ISO instants"
    (should= "2026-04-01T00:00:00Z" (sut/parse-bound :since "2026-04-01"))
    (should= "2026-04-01T05:00:00Z" (sut/parse-bound :until "2026-04-01T01:00:00-04:00")))
  (it "refuses an invalid --until before starting a dream"
    (let [err (java.io.StringWriter.)]
      (should= 1 (binding [*err* err]
                   (sut/run (assoc @opts :_raw-args ["run" "--crew" "ketch" "--until" "tomorrow"]))))
      (should-contain "invalid --until: tomorrow" (str err))))
  (it "approves a proposed habit"
    (let [id (:id (habits/propose! @fs* "/dream-test" "ketch" "Keep watch." ["deck"] :manual))]
      (should= 0 (sut/run (assoc @opts :_raw-args ["approve" id "--crew" "ketch"])))
      (should= :active (:state (first (habits/list-habits @fs* "/dream-test" "ketch"))))))
  (it "refuses an unknown crew"
    (should= 1 (binding [*err* (java.io.StringWriter.)]
                   (sut/run (assoc @opts :_raw-args ["wipe" "--crew" "../other"])))))  (it "shows recent dreams in reverse chronological order"
    (fs/mkdirs @fs* "/dream-test/dream/ketch/diary")
    (fs/spit @fs* "/dream-test/dream/ketch/diary/2026-04-21.edn"
             "{:at \"2026-04-21T03:00:00Z\" :status :succeeded :sessions [\"deck\"]}")
    (should= 0 (binding [*out* (java.io.StringWriter.)]
                 (sut/run (assoc @opts :_raw-args ["diary" "--crew" "ketch"])))))

  (it "shows computed strength and pin state"
    (habits/save! @fs* "/dream-test" "ketch" {:id "watch" :state :active :pinned true
                                                  :lesson "Keep watch." :history [{:at "2026-04-01T00:00:00Z" :event :approved}]})
    (let [output (with-out-str (should= 0 (sut/run (assoc @opts :_raw-args ["show" "watch" "--crew" "ketch"]))))]
      (should-contain "Strength: 2.0" output)
      (should-contain "Pinned: yes" output)))

  (it "unpins a habit while retaining its history"
    (habits/save! @fs* "/dream-test" "ketch" {:id "watch" :state :active :pinned true :lesson "Keep watch."})
    (should= 0 (sut/run (assoc @opts :_raw-args ["unpin" "watch" "--crew" "ketch"])))
    (should= false (:pinned (habits/find-habit @fs* "/dream-test" "ketch" "watch"))))

)
