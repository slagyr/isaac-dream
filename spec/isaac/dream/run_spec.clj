(ns isaac.dream.run-spec
  (:require
    [clojure.edn :as edn]
    [isaac.agent.config.resolve :as resolve]
    [isaac.agent.drive.dispatch :as dispatch]
    [isaac.agent.session.store.spi :as store]
    [isaac.dream.habits :as habits]
    [isaac.dream.run :as sut]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(defn dream-with-reply
  ([reply] (dream-with-reply reply nil))
  ([reply seed!]
  (let [fs* (fs/mem-fs)
        request (atom nil)
        transcript [{:id "e-1" :type "message" :timestamp "2026-04-21T14:00:00Z"
                     :message {:role "user" :content "Always water the moonflowers first."}}]]
    (when seed! (seed! fs*))
    (with-redefs [store/list-sessions (fn [_] [{:id "greenhouse" :crew "hieronymus"}])
                  store/chronicle-transcript (fn [_ _] transcript)
                  resolve/resolve-crew-context (fn [& _] {:provider :grover :model "echo" :soul "Ship botanist"})
                  dispatch/dispatch-chat (fn [_ message] (reset! request message) {:content reply})]
      (try
        (sut/run! {:fs fs* :root "/dream-test" :cfg {:crew {"hieronymus" {}}}
                   :crew "hieronymus" :session-store :fake :now "2026-04-22T03:00:00Z"})
        (catch Exception _ nil))
      {:request @request
       :habits (habits/list-habits fs* "/dream-test" "hieronymus")
       :diary (edn/read-string (fs/slurp fs* "/dream-test/dream/hieronymus/diary/2026-04-22T03-00-00Z.edn"))}))))

(defn seed-moonflowers! [fs*]
  (habits/propose! fs* "/dream-test" "hieronymus" "Water moonflowers first."
                   [{:session "greenhouse" :entries ["old"]}] :auto {:id "moonflowers"}))

(describe "Dream model replies"
  (it "turns a proposal using a proposed habit's id into reinforcement rather than a new proposal"
    (let [seed! (fn [fs*] (habits/propose! fs* "/dream-test" "hieronymus" "Water the moonflowers first."
                                           [{:session "greenhouse" :entries ["old"]}] :manual
                                           {:id "moonflowers"}))
          {:keys [habits diary]} (dream-with-reply
                                   "{\"propose\":[{\"id\":\"moonflowers\",\"lesson\":\"Water moonflowers before ferns.\",\"evidence\":[\"greenhouse#1\"]}],\"reinforce\":[]}"
                                   seed!)]
      (should= ["moonflowers"] (:reinforced diary))
      (should= [] (:proposed diary))
      (should= "Water the moonflowers first." (:lesson (first habits)))
      (should= :reinforced (:event (last (:history (first habits)))))))
  (it "rejects an existing-id proposal with no evidence from this window"
    (let [seed! (fn [fs*] (habits/propose! fs* "/dream-test" "hieronymus" "Water first."
                                           [{:session "greenhouse" :entries ["old"]}] :manual
                                           {:id "moonflowers"}))
          {:keys [habits diary]} (dream-with-reply
                                   "{\"propose\":[{\"id\":\"moonflowers\",\"lesson\":\"Water first.\",\"evidence\":[\"other#9\"]}],\"reinforce\":[]}"
                                   seed!)]
      (should= [] (:reinforced diary))
      (should= [:proposed] (mapv :event (:history (first habits))))))
  (it "stores a cited lesson from a prose-led JSON fence"
    (let [{:keys [habits diary request]} (dream-with-reply
                                          (str "Here are the lessons:\n```json\n"
                                               "{\"propose\":[{\"id\":\"moonflowers\",\"lesson\":\"Water the moonflowers first.\","
                                               "\"evidence\":[\"greenhouse#1\"],\"supersedes\":[]}],\"reinforce\":[]}\n```"))]
      (should= "succeeded" (:status diary))
      (should= "moonflowers" (:id (first habits)))
      (should= [{:session "greenhouse" :entries ["e-1"]}] (:evidence (first habits)))
      (should-contain "greenhouse#1 2026-04-21T14:00:00Z user: Always water the moonflowers first."
                      (get-in request [:messages 0 :content]))))
  (it "includes the exact answer shape in the model prompt"
    (let [prompt (get-in (:request (dream-with-reply "{\"propose\":[],\"reinforce\":[]}")) [:messages 0 :content])]
      (should-contain "\"propose\":[{\"id\":\"short-slug\",\"lesson\":" prompt)
      (should-contain "\"evidence\":[\"<session>#<n>\"],\"supersedes\":[\"existing-habit-id\"]" prompt)
      (should-contain "\"reinforce\":[{\"id\":\"existing-habit-id\",\"evidence\":[\"<session>#<n>\"],\"kind\":\"taught|applied\"}]" prompt)
      (should-contain "{\"propose\":[],\"reinforce\":[],\"contradict\":[]}" prompt)
      (should-contain "greenhouse#1" prompt)
      (should-contain "Ship botanist" prompt)))
  (it "records an applied reinforcement only when its evidence cites an assistant reply"
    (let [{:keys [habits diary]} (dream-with-reply
                                  "{\"reinforce\":[{\"id\":\"moonflowers\",\"kind\":\"applied\",\"evidence\":[\"greenhouse#1\"]}]}"
                                  seed-moonflowers!)]
      (should= [] (:reinforced diary))
      (should= :applied-without-reply (:reason (first (:dropped diary))))
      (should= :approved (:event (last (:history (first habits)))))))
  (it "records a taught reinforcement by default"
    (let [{:keys [habits]} (dream-with-reply
                            "{\"reinforce\":[{\"id\":\"moonflowers\",\"evidence\":[\"greenhouse#1\"]}]}"
                            seed-moonflowers!)]
      (should= :taught (:kind (last (:history (first habits)))))))
  (it "records a contradiction against an active habit without retiring it"
    (let [{:keys [habits diary]} (dream-with-reply
                                  "{\"contradict\":[{\"id\":\"moonflowers\",\"evidence\":[\"greenhouse#1\"]}]}"
                                  seed-moonflowers!)]
      (should= ["moonflowers"] (:contradicted diary))
      (should= :active (:state (first habits)))
      (should= :contradicted (:event (last (:history (first habits)))))))
  (it "ignores contradictions without cited window evidence"
    (let [{:keys [habits diary]} (dream-with-reply
                                  "{\"contradict\":[{\"id\":\"moonflowers\",\"evidence\":[\"elsewhere#3\"]}]}"
                                  seed-moonflowers!)]
      (should= [] (:contradicted diary))
      (should= :approved (:event (last (:history (first habits)))))))
  (it "records a clear failure with the beginning of a prose-only reply"
    (let [{:keys [diary]} (dream-with-reply "No lasting lessons today, thanks.")]
      (should= "failed" (:status diary))
      (should-contain "No JSON object" (:error diary))
      (should-contain "No lasting lessons today" (:error diary))))
  (it "accepts prose before and after an unfenced JSON object"
    (let [{:keys [diary]} (dream-with-reply "Result: {\"propose\":[],\"reinforce\":[]} End.")]
      (should= "succeeded" (:status diary))))
  (it "skips an invalid brace in the lead-in before the JSON"
    (let [{:keys [diary]} (dream-with-reply "Look {here}: {\"propose\":[],\"reinforce\":[]}")]
      (should= "succeeded" (:status diary)))))

(describe "Dream window"
  (it "labels only user and assistant text, never tool output"
    (let [window (sut/window [{:id "greenhouse" :crew "h" :entries
                               [{:id "e-1" :type "message" :timestamp "2026-04-21T14:00:00Z"
                                 :message {:role "user" :content "Water first."}}
                                {:id "e-2" :type "toolResult" :timestamp "2026-04-21T14:00:01Z"
                                 :message {:role "toolResult" :content "secret"}}
                                {:id "e-3" :type "message" :timestamp "2026-04-21T14:00:02Z"
                                 :message {:role "assistant" :content "Noted."}}]}] nil "2026-04-22T03:00:00Z")]
      (should= ["greenhouse#1 2026-04-21T14:00:00Z user: Water first."
                "greenhouse#2 2026-04-21T14:00:02Z assistant: Noted."] (:lines window))
      (should= [{:session "greenhouse" :entries ["e-1"]}]
               (sut/evidence window ["greenhouse#1" "greenhouse#9"])))))

(describe "Dream config"
  (it "keeps dreaming off until enabled and inherits the crew default schedule"
    (should= {:enabled false :approval :manual :batch 400 :schedule "0 3 * * *"}
             (sut/settings {:defaults {:crew {:dream {:schedule "0 3 * * *"}}}
                            :crew {"ketch" {:model "grover"}}} "ketch")))
  (it "overrides fleet auto approval for a manual crew"
    (should= :manual (:approval (sut/settings {:defaults {:crew {:dream {:approval :auto}}}
                                               :crew {"ketch" {:dream {:approval :manual}}}} "ketch")))))

(describe "Dream window safety"
  (it "drops tool-call content from an assistant message without dropping its text"
    (let [window (sut/window [{:id "deck" :entries
                               [{:id "e-1" :type "message" :timestamp "2026-04-21T14:00:00Z"
                                 :message {:role "assistant" :content [{:type "text" :text "Noted."}
                                                                       {:type "toolCall" :arguments "secret"}]}}]}]
                             nil "2026-04-22T03:00:00Z")]
      (should= ["deck#1 2026-04-21T14:00:00Z assistant: Noted."] (:lines window))))
  (it "retains the earliest transcript messages when the window is full"
    (let [messages (for [n (range 401)]
                     {:id (str "e-" n) :type "message" :timestamp (format "2026-04-21T14:%02d:%02dZ" (quot n 60) (mod n 60))
                      :message {:role "user" :content (str n)}})
          window (sut/window [{:id "deck" :entries messages}] nil "2026-04-22T03:00:00Z")]
      (should= 401 (count (:lines window)))
      (should= "deck#1 2026-04-21T14:00:00Z user: 0" (first (:lines window)))
      (should= "deck#401 2026-04-21T14:06:40Z user: 400" (last (:lines window))))))

(describe "Dream batches"
  (it "keeps equal timestamps together and labels across batches"
    (let [sessions [{:id "deck" :entries (mapv (fn [n t] {:id (str "e-" n) :type "message" :timestamp t
                                                       :message {:role "user" :content (str n)}})
                                                 (range 4) ["2026-04-21T01:00:00Z" "2026-04-21T01:01:00Z"
                                                            "2026-04-21T01:01:00Z" "2026-04-21T01:02:00Z"])}]
          batches (sut/batches (sut/window sessions nil "2026-04-22T00:00:00Z") 2)]
      (should= [3 1] (mapv #(count (:lines %)) batches))
      (should= ["deck#1" "deck#2" "deck#3" "deck#4"] (mapv :label (mapcat :entries batches)))
      (should= "2026-04-21T01:01:00Z" (:until (first batches))))))

(describe "Dream watermark"
  (it "advances through batches without moving backward"
    (should= "2026-04-22T00:00:00Z" (sut/later "2026-04-22T00:00:00Z" "2026-04-21T00:00:00Z"))
    (should= "2026-04-23T00:00:00Z" (sut/later "2026-04-22T00:00:00Z" "2026-04-23T00:00:00Z"))))
