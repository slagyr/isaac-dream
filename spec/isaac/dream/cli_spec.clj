(ns isaac.dream.cli-spec
  (:require
    [isaac.dream.cli :as sut]
    [isaac.dream.habits :as habits]
    [isaac.foundation.fs :as fs]
    [speclj.core :refer :all]))

(describe "Operator habit commands"
  (with fs* (fs/mem-fs))
  (with opts {:root "/dream-test" :fs @fs* :config {:crew {"ketch" {:model "grover"}}}})
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

)
