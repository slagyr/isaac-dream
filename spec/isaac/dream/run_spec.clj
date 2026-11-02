(ns isaac.dream.run-spec
  (:require
    [isaac.dream.run :as sut]
    [speclj.core :refer :all]))

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
