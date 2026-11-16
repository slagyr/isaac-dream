(ns isaac.dream.tools
  (:require
    [clojure.string :as str]
    [isaac.agent.session.store.spi :as store]
    [isaac.agent.tool.fs-bounds :as bounds]
    [isaac.dream.habits :as habits]
    [isaac.dream.background :as background]
    [isaac.dream.run :as dream-run]
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

(defn habit-tool [args]
  (try
    (let [args (bounds/string-key-map args)
          ss (bounds/session-store args)
          crew (:crew (store/get-session ss (get args "session_key")))]
      (if-not crew
        {:result "not found"}
        (let [fs* (bounds/filesystem args)
              root (bounds/root args)
              cfg (or (loader/snapshot "dream habit") {})
              strength-config (:strength (dream-run/settings cfg crew))
              id (get args "id")]
          {:result (if id
                     (if-let [habit (habits/find-habit fs* root crew id)]
                       (background/render habit crew ss strength-config
                                          (habits/ranking-days fs* root crew [habit]))
                       "not found")
                     (str/join "\n"
                       (let [all (habits/list-habits fs* root crew)
                           days (habits/ranking-days fs* root crew all)]
                       (for [habit (sort-by :id all)]
                         (str (:id habit) " " (name (keyword (:state habit)))
                              " Strength: " (format "%.1f" (habits/strength habit days strength-config))
                              " " (if (:pinned habit) "pinned" "unpinned") " " (:lesson habit))))))})))
    (catch Exception _ {:result "not found"})))

(defn habit-tool-factory [_]
  {:description "Read the calling crew's own habits and their background. Omit id to list habits."
   :builtin? true
   :parameters {:type "object" :properties {"id" {:type "string"}}}
   :handler #'habit-tool})
