(ns isaac.dream.cli
  (:require
    [clojure.edn :as edn]
    [clojure.string :as str]
    [clojure.tools.cli :as tools-cli]
    [isaac.dream.habits :as habits]
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
                  [nil "--state STATE" "Filter habit state"]
                  [nil "--lesson LESSON" "Approve with replacement lesson"]
                  ["-h" "--help" "Show help"]])

(defn- crews [cfg fs* root-dir]
  (->> (concat (keys (:crew cfg)) (fs/children fs* (str root-dir "/config/crew")))
       (map #(str/replace (name %) #"\.edn$" "")) distinct sort))

(defn- require-crew! [cfg crew]
  (when-not (or (get-in cfg [:crew crew]) (get-in cfg [:crew (keyword crew)]))
    (throw (ex-info (str "unknown crew: " crew) {}))))

(defn- print-habit! [fs* root-dir crew habit]
  (println crew (:id habit) (name (:state habit)) (:lesson habit)
           (str/join "," (map :session (:evidence habit))) (pr-str (:supersedes habit))))

(defn- digest! [cfg crew proposals error]
  (let [cfg (or cfg (loader/load-config! (loader/root) (fs/instance) "dream digest"))
        {:keys [comm to]} (or (:digest (dream-run/settings cfg crew))
                              (let [{:keys [comm target]} (get-in cfg [:attention :notify])]
                                {:comm comm :to target}))]
    (when (and comm to)
      (delivery/enqueue! {:comm (keyword comm) :target to
                          :content (if error
                                     (str crew " dream failed: " error)
                                     (str crew " dreamed: "
                                          (str/join "; " (map (fn [{:keys [id lesson]}]
                                                               (str id ": " lesson " — dream approve " id " --crew " crew)) proposals))))
                          :origin {:kind :dream} :crew crew}))))

(defn- diary! [fs* root-dir crew]
  (let [dir (str root-dir "/dream/" crew "/diary")]
    (doseq [file (reverse (sort (fs/children fs* dir)))]
      (let [{:keys [at status sessions proposed]} (edn/read-string (fs/slurp fs* (str dir "/" file)))]
        (println at (name (keyword status)) (count sessions) (if (= 1 (count sessions)) "session" "sessions")
                 (when (seq proposed) (str "proposed: " (str/join ", " proposed))))))))

(defn run [opts]
  (let [[sub & args] (:_raw-args opts)
        {:keys [options arguments errors]} (tools-cli/parse-opts args option-spec)
        crew (:crew options)
        fs* (or (:fs opts) (fs/instance) (fs/real-fs))
        root-dir (or (:root opts) (root/default-root opts))]
    (try
      (let [cfg (or (:config opts) (loader/load-config! root-dir fs* "dream CLI") {})]
        (cond
          (:help options) (do (println "isaac dream run|diary|show|list|approve|reject|retire|wipe") 0)
          (seq errors) (throw (ex-info (str/join "; " errors) {}))
          (and crew (not (re-matches #"[a-zA-Z0-9_-]+" crew))) (throw (ex-info "invalid crew" {}))
          (= sub "list") (do (when crew (require-crew! cfg crew))
                             (doseq [c (if crew [crew] (crews cfg fs* root-dir))
                                     habit (habits/list-habits fs* root-dir c)
                                     :when (or (nil? (:state options)) (= (:state options) (name (:state habit))))]
                               (print-habit! fs* root-dir c habit))
                             0)
          :else (do
                  (when-not crew (throw (ex-info "--crew is required" {})))
                  (require-crew! cfg crew)
                  (case sub
                    "run" (let [result (dream-run/run! {:fs fs* :root root-dir :cfg cfg :crew crew
                                                          :now (str (memory/now))
                                                          :notify! (partial digest! cfg)})]
                              (when (= :empty (:status result)) (println "no new messages")) 0)
                    "diary" (do (diary! fs* root-dir crew) 0)
                    "show" (let [habit (habits/find-habit fs* root-dir crew (first arguments))]
                              (when-not habit (throw (ex-info "Habit not found" {})))
                              (println (pr-str habit))
                              (when-let [ss (or (get-in opts [:sessions :store]) (store/registered-store))]
                                (doseq [{:keys [session entries]} (:evidence habit)]
                                  (let [record (store/get-session ss session)
                                        transcript (when (= crew (:crew record)) (store/chronicle-transcript ss session))]
                                    (doseq [id entries]
                                      (if-let [entry (first (filter #(= id (:id %)) transcript))]
                                        (println session (str (clojure.string/replace (:timestamp entry) #"(?<!Z)$" "Z")) (str (get-in entry [:message :role]) ":")
                                                 (let [content (get-in entry [:message :content])]
                                                   (if (string? content) content (str/join "" (map :text content)))))
                                        (println session "missing evidence" id))))))
                              0)
                    "wipe" (do (habits/wipe! fs* root-dir crew) 0)
                    ("approve" "reject" "retire")
                    (do (if (and (= sub "approve") (:lesson options))
                          (let [old (or (habits/find-habit fs* root-dir crew (first arguments))
                                        (throw (ex-info "Habit not found" {})))
                                id (str (:id old) "-" (subs (str (java.util.UUID/randomUUID)) 0 8))]
                            (habits/propose! fs* root-dir crew (:lesson options) (:evidence old) :auto
                                             {:id id :dream (:dream old) :supersedes [(:id old)]})
                            (habits/change-state! fs* root-dir crew id :active))
                          (habits/change-state! fs* root-dir crew (first arguments)
                                                ({"approve" :active "reject" :rejected "retire" :retired} sub))) 0)
                    (throw (ex-info "Unknown dream subcommand" {}))))))
      (catch Exception e
        (binding [*out* *err*] (println (ex-message e)))
        1))))

(defmethod cli-api/run :dream [_ opts] (run opts))
(defmethod cli-api/option-spec :dream [_] option-spec)
