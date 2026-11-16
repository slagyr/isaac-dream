(ns isaac.dream.cli
  (:require
    [clojure.edn :as edn]
    [clojure.string :as str]
    [clojure.tools.cli :as tools-cli]
    [isaac.dream.habits :as habits]
    [isaac.dream.background :as background]
    [isaac.dream.run :as dream-run]
    [isaac.agent.comm.delivery.queue :as delivery]
    [isaac.agent.tool.memory :as memory]
    [isaac.agent.session.store.spi :as store]
    [isaac.foundation.config.loader :as loader]
    [isaac.foundation.cli.api :as cli-api]
    [isaac.foundation.config.root :as root]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.nexus :as nexus]))

(def option-spec [[nil "--crew CREW" "Crew whose habits to manage"]
                  [nil "--since INSTANT" "Window start (ISO instant or UTC date)"]
                  [nil "--until INSTANT" "Window end (ISO instant or UTC date)"]
                  [nil "--state STATE" "Filter habit state"]
                  [nil "--lesson LESSON" "Approve with replacement lesson"]
                  ["-h" "--help" "Show help"]])

(defn- crews [cfg fs* root-dir]
  (->> (concat (keys (:crew cfg)) (fs/children fs* (str root-dir "/config/crew")))
       (map #(str/replace (name %) #"\.edn$" "")) distinct sort))

(defn- require-crew! [cfg crew]
  (when-not (or (get-in cfg [:crew crew]) (get-in cfg [:crew (keyword crew)]))
    (throw (ex-info (str "unknown crew: " crew) {}))))

(defn- print-habit! [crew habit]
  (println crew (:id habit) (name (:state habit)) (:lesson habit)
           (str/join "," (map :session (:evidence habit))) (pr-str (:supersedes habit))))

(defn- digest! [cfg fs* root-dir crew proposals error & [contradicted retired retire-proposed]]
  (let [cfg (or cfg (loader/load-config! (loader/root) (fs/instance) "dream digest"))
        {:keys [comm to]} (or (:digest (dream-run/settings cfg crew))
                              (let [{:keys [comm target]} (get-in cfg [:attention :notify])]
                                {:comm comm :to target}))]
    (when (and comm to)
      (delivery/enqueue! {:comm (keyword comm) :target to
                          :content (if error
                                     (str crew " dream failed: " error)
                                     (str crew " dreamed: "
                                          (str/join "; " (concat (map (fn [{:keys [id lesson]}]
                                                                 (str id ": " lesson " — dream approve " id " --crew " crew)) proposals)
                                                         (map (fn [id] (str id ": " (:lesson (habits/find-habit fs* root-dir crew id))
                                                                            " contradicted — dream retire " id " --crew " crew))
                                                              (remove (set retired) contradicted))
                                                         (map (fn [id] (str id ": retired — dream approve " id " --crew " crew)) retired)
                                                         (map (fn [id] (str id ": faded — dream retire " id " --crew " crew)) retire-proposed)))))
                          :origin {:kind :dream} :crew crew}))))

(defn- diary! [fs* root-dir crew]
  (let [dir (str root-dir "/dream/" crew "/diary")]
    (doseq [file (reverse (sort (fs/children fs* dir)))]
      (let [{:keys [at status sessions proposed]} (edn/read-string (fs/slurp fs* (str dir "/" file)))]
        (println at (name (keyword status)) (count sessions) (if (= 1 (count sessions)) "session" "sessions")
                 (when (seq proposed) (str "proposed: " (str/join ", " proposed))))))))

(defn parse-bound [flag value]
  (when value
    (try
      (str (if (re-matches #"\d{4}-\d{2}-\d{2}" value)
             (.toInstant (.atStartOfDay (java.time.LocalDate/parse value) java.time.ZoneOffset/UTC))
             (java.time.Instant/parse value)))
      (catch Exception _ (throw (ex-info (str "invalid --" (name flag) ": " value) {}))))))

(defn run [opts]
  (let [[sub & args] (:_raw-args opts)
        {:keys [options arguments errors]} (tools-cli/parse-opts args option-spec)
        crew (:crew options)
        fs* (or (:fs opts) (fs/instance) (fs/real-fs))
        root-dir (or (:root opts) (root/default-root opts))]
    (try
      (let [cfg (or (:config opts) (loader/load-config! root-dir fs* "dream CLI") {})]
        (cond
          (:help options) (do (println "isaac dream run|condense|diary|show|list|approve|reject|retire|pin|unpin|wipe") 0)
          (seq errors) (throw (ex-info (str/join "; " errors) {}))
          (and crew (not (re-matches #"[a-zA-Z0-9_-]+" crew))) (throw (ex-info "invalid crew" {}))
          (= sub "list") (do (when crew (require-crew! cfg crew))
                             (doseq [c (if crew [crew] (crews cfg fs* root-dir))
                                     habit (habits/list-habits fs* root-dir c)
                                     :when (or (nil? (:state options)) (= (:state options) (name (:state habit))))]
                               (print-habit! c habit))
                             0)
          :else (do
                  (when-not crew (throw (ex-info "--crew is required" {})))
                  (require-crew! cfg crew)
                  (case sub
                    "run" (let [since (parse-bound :since (:since options))
                                until (parse-bound :until (:until options))
                                result (dream-run/run! {:fs fs* :root root-dir :cfg cfg :crew crew
                                                          :now (str (memory/now)) :since since :until until
                                                          :notify! (partial digest! cfg fs* root-dir)})]
                              (when (= :empty (:status result)) (println "no new messages")) 0)
                    "condense" (let [{:keys [revisions dropped]} (dream-run/condense! {:fs fs* :root root-dir :cfg cfg :crew crew})]
                                 (doseq [{:keys [id reason]} dropped] (println id (name reason)))
                                 (when (seq revisions) (digest! cfg fs* root-dir crew revisions nil))
                                 0)
                    "diary" (do (diary! fs* root-dir crew) 0)
                    "show" (let [habit (habits/find-habit fs* root-dir crew (first arguments))]
                              (when-not habit (throw (ex-info "Habit not found" {})))
                              (println (background/render habit crew
                                         (or (get-in opts [:sessions :store]) (store/registered-store))
                                         (:strength (dream-run/settings cfg crew))))
                              0)
                    "wipe" (do (habits/wipe! fs* root-dir crew) 0)
                    "pin" (do (habits/pin! fs* root-dir crew (first arguments) true) 0)
                    "unpin" (do (habits/pin! fs* root-dir crew (first arguments) false) 0)
                    ("approve" "reject" "retire")
                    (do (if (and (= sub "approve") (:lesson options))
                          (let [old (or (habits/find-habit fs* root-dir crew (first arguments))
                                        (throw (ex-info "Habit not found" {})))
                                id (str (:id old) "-" (subs (str (java.util.UUID/randomUUID)) 0 8))]
                            (habits/propose! fs* root-dir crew (:lesson options) (:evidence old) :auto
                                             {:id id :dream (:dream old) :supersedes [(:id old)]})
                            (habits/change-state! fs* root-dir crew id :active))
                          (let [id (first arguments)
                                habit (habits/find-habit fs* root-dir crew id)]
                            (cond
                              (and (:revision habit) (= sub "approve")) (habits/approve-revision! fs* root-dir crew id)
                              (and (:revision habit) (= sub "reject")) (habits/reject-revision! fs* root-dir crew id)
                              :else (habits/change-state! fs* root-dir crew id
                                                         ({"approve" :active "reject" :rejected "retire" :retired} sub))))) 0)
                    (throw (ex-info "Unknown dream subcommand" {}))))))
      (catch Exception e
        (binding [*out* *err*] (println (ex-message e)))
        1))))

(defmethod cli-api/run :dream [_ opts] (run opts))
(defmethod cli-api/option-spec :dream [_] option-spec)
