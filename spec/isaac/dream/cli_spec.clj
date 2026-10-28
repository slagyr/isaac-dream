(ns isaac.dream.cli-spec
  (:require
    [isaac.dream.cli :as sut]
    [isaac.dream.habits :as habits]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(describe "Operator habit commands"
  (with fs* (fs/mem-fs))
  (with opts {:root "/dream-test" :fs @fs*})
  (it "approves a proposed habit"
    (let [id (:id (habits/propose! @fs* "/dream-test" "ketch" "Keep watch." ["deck"] :manual))]
      (should= 0 (sut/run (assoc @opts :_raw-args ["approve" id "--crew" "ketch"])))
      (should= :active (:state (first (habits/list-habits @fs* "/dream-test" "ketch"))))))
  (it "refuses an unknown crew"
    (should= 1 (binding [*err* (java.io.StringWriter.)]
                   (sut/run (assoc @opts :_raw-args ["wipe" "--crew" "../other"]))))))
