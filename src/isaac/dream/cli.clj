(ns isaac.dream.cli
  (:require
    [clojure.string :as str]
    [clojure.tools.cli :as tools-cli]
    [isaac.dream.habits :as habits]
    [isaac.foundation.cli.api :as cli-api]
    [isaac.foundation.config.root :as root]
    [isaac.foundation.fs :as fs]))

(def option-spec [[nil "--crew CREW" "Crew whose habits to manage"]
                  ["-h" "--help" "Show help"]])

(defn run [opts]
  (let [[sub & args] (:_raw-args opts)
        {:keys [options arguments errors]} (tools-cli/parse-opts args option-spec)
        crew (:crew options)
        fs* (or (:fs opts) (fs/instance) (fs/real-fs))
        root-dir (or (:root opts) (root/default-root opts))]
    (try
      (cond
        (:help options) (do (println "isaac dream list|approve|reject|retire|wipe --crew CREW") 0)
        (seq errors) (throw (ex-info (str/join "; " errors) {}))
        (not (re-matches #"[a-zA-Z0-9_-]+" (or crew ""))) (throw (ex-info "--crew is required" {}))
        (= sub "list") (do (doseq [{:keys [id state lesson]} (habits/list-habits fs* root-dir crew)]
                              (println id (name state) lesson)) 0)
        (= sub "wipe") (do (habits/wipe! fs* root-dir crew) 0)
        (#{"approve" "reject" "retire"} sub)
        (do (habits/change-state! fs* root-dir crew (first arguments)
                                  (case sub "approve" :active "reject" :rejected "retire" :retired)) 0)
        :else (throw (ex-info "Unknown dream subcommand" {})))
      (catch Exception e
        (binding [*out* *err*] (println (ex-message e)))
        1))))

(defmethod cli-api/run :dream [_ opts] (run opts))
(defmethod cli-api/option-spec :dream [_] option-spec)
