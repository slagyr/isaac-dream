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
      (let [cfg-crew (or (get-in cfg [:crew crew]) (get-in cfg [:crew (keyword crew)]))
            approval (or (get-in cfg-crew [:dream :approval])
                         (get-in cfg [:defaults :crew :dream :approval]) :manual)
            transcript (store/chronicle-transcript (bounds/session-store args) (get args "session_key"))
            entry (last (filter #(and (= "message" (:type %))
                                      (= "user" (get-in % [:message :role]))) transcript))
            evidence (when (:id entry) [{:session (get args "session_key") :entries [(:id entry)]}])
            habit (habits/propose! (bounds/filesystem args) (bounds/root args) crew
                                   (get args "lesson") evidence approval)]
        {:result (str "Habit " (:id habit) " " (name (:state habit)))})
      (catch Exception e
        {:isError true :error (ex-message e)}))))

(defn propose-tool-factory [_]
  {:description "Propose a crew-private habit learned from sessions. Evidence is attached from the calling message."
   :builtin? true
   :parameters {:type "object"
                :properties {"lesson" {:type "string"}
}
                :required ["lesson"]}
   :handler #'propose-tool})
