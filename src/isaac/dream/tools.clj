(ns isaac.dream.tools
  (:require
    [isaac.agent.session.store.spi :as store]
    [isaac.agent.tool.fs-bounds :as bounds]
    [isaac.dream.habits :as habits]
    [isaac.foundation.config.loader :as loader]))

(defn propose-tool [args]
  (let [args     (bounds/string-key-map args)
        session (store/get-session (bounds/session-store args) (get args "session_key"))
        crew    (:crew session)
        cfg     (loader/snapshot "dream propose")]
    (try
      (when-not crew
        (throw (ex-info "calling session has no crew" {})))
      (let [approval (or (get-in cfg [:dream crew :approval])
                         (get-in cfg [:dream (keyword crew) :approval]) :manual)
            habit    (habits/propose! (bounds/filesystem args) (bounds/root args) crew
                                     (get args "lesson") (get args "evidence") approval)]
        {:result (str "Habit " (:id habit) " " (name (:state habit)))})
      (catch Exception e
        {:isError true :error (ex-message e)}))))

(defn propose-tool-factory [_]
  {:description "Propose a crew-private habit learned from sessions. Requires evidence."
   :builtin? true
   :parameters {:type "object"
                :properties {"lesson" {:type "string"}
                             "evidence" {:type "array" :items {:type "string"}}}
                :required ["lesson" "evidence"]}
   :handler #'propose-tool})
