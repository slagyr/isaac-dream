(ns isaac.dream.tools-spec
  (:require
    [isaac.dream.habits :as habits]
    [isaac.dream.tools :as sut]
    [isaac.agent.session.store.spi :as store]
    [isaac.foundation.config.loader :as loader]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(describe "dream__propose"
  (with fs* (fs/mem-fs))
  (it "rejects missing evidence before writing a habit"
    (with-redefs [store/get-session (fn [& _] {:crew "ketch"})
                  loader/snapshot (fn [& _] {})]
      (should (:isError (sut/propose-tool {"lesson" "Keep watch." "session_key" "deck"
                                           "state_dir" "/dream-test" "fs" @fs* "session_store" :stub})))
      (should= [] (habits/list-habits @fs* "/dream-test" "ketch"))))
  (it "promotes valid proposals only when configured for auto approval"
    (with-redefs [store/get-session (fn [& _] {:crew "ketch"})
                  loader/snapshot (fn [& _] {:dream {"ketch" {:approval :auto}}})]
      (sut/propose-tool {"lesson" "Keep watch." "evidence" ["deck"] "session_key" "deck"
                         "state_dir" "/dream-test" "fs" @fs* "session_store" :stub})
      (should= :active (:state (first (habits/list-habits @fs* "/dream-test" "ketch")))))))
