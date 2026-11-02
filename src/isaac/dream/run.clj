(ns isaac.dream.run
  (:require
    [cheshire.core :as json]
    [clojure.edn :as edn]
    [clojure.string :as str]
    [isaac.agent.config.resolve :as resolve]
    [isaac.agent.drive.dispatch :as dispatch]
    [isaac.agent.session.store.spi :as store]
    [isaac.agent.session.store.sidecar :as sidecar-store]
    [isaac.agent.tool.memory :as memory]
    [isaac.foundation.logger :as log]
    [isaac.dream.habits :as habits]
    [isaac.foundation.config.loader :as loader]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.nexus :as nexus]
    [isaac.foundation.scheduler.runtime :as scheduler]
    [isaac.foundation.reconfigurable :as reconfigurable]))

(defn settings [cfg crew]
  (let [defaults (get-in cfg [:defaults :crew :dream])
        specific (:dream (or (get-in cfg [:crew crew]) (get-in cfg [:crew (keyword crew)])))]
    (merge {:enabled false :approval :manual :batch 400} defaults specific)))

(defn check-schedules [{:keys [config]}]
  {:errors (vec (for [[crew _] (:crew config)
                      :let [dream (settings config crew)]
                      :when (and (:enabled dream) (str/blank? (:schedule dream)))]
                  {:key (str "crew." (name crew) ".dream.schedule")
                   :value (str "crew." (name crew) ".dream.schedule required when dream.enabled is true")
                   :file (str "config/crew/" (name crew) ".edn")}))
   :warnings []})

(defn window [sessions since until]
  (let [entries (->> sessions
                     (mapcat (fn [{:keys [id entries]}]
                               (for [entry entries
                                     :let [role (get-in entry [:message :role])
                                           content (get-in entry [:message :content])
                                           text (if (string? content) content
                                                  (when (sequential? content)
                                                    (str/join "" (keep #(when (= "text" (:type %)) (:text %)) content))))
                                           timestamp (some-> (:timestamp entry) (str/replace #"(?<!Z)$" "Z"))]
                                     :when (and (= "message" (:type entry))
                                                (#{"user" "assistant"} role)
                                                (string? text)
                                                (not (str/blank? text))
                                                timestamp
                                                (or (nil? since) (pos? (compare timestamp since)))
                                                (not (pos? (compare timestamp until))))]
                                 (assoc entry :session id :role role :text text :timestamp timestamp))))
                     (sort-by (juxt :timestamp :session))
                     vec)
        counters (atom {})
        labelled (mapv (fn [entry]
                         (let [n (get (swap! counters update (:session entry) (fnil inc 0)) (:session entry))]
                           (assoc entry :label (str (:session entry) "#" n)))) entries)]
    {:entries labelled
     :lines (mapv #(str (:label %) " " (:timestamp %) " " (:role %) ": " (:text %)) labelled)
     :labels (into {} (map (juxt :label identity) labelled))
     :sessions (vec (distinct (map :session labelled)))}))

(defn batches [window size]
  (when-not (pos? size) (throw (ex-info "dream.batch must be positive" {:batch size})))
  (loop [remaining (:entries window) result []]
    (if (empty? remaining)
      result
      (let [initial (take size remaining)
            end (:timestamp (last initial))
            entries (vec (concat initial (take-while #(= end (:timestamp %)) (drop size remaining))))]
        (recur (drop (count entries) remaining)
               (conj result {:entries entries
                             :until end
                             :lines (mapv #(str (:label %) " " (:timestamp %) " " (:role %) ": " (:text %)) entries)
                             :labels (into {} (map (juxt :label identity) entries))
                             :sessions (vec (distinct (map :session entries)))}))))))

(defn later [old candidate]
  (if (and old (or (nil? candidate) (pos? (compare old candidate)))) old candidate))

(defn evidence [window labels]
  (->> labels
       (keep #(get-in window [:labels %]))
       (group-by :session)
       (map (fn [[session entries]] {:session session :entries (mapv :id entries)}))
       (sort-by :session)
       vec))

(defn- state-path [root crew] (str root "/dream/" crew "/state.edn"))
(defn- read-state [fs* root crew]
  (let [path (state-path root crew)]
    (if (fs/file? fs* path) (edn/read-string (fs/slurp fs* path)) {})))
(defn- write-state! [fs* root crew state]
  (fs/mkdirs fs* (str root "/dream/" crew))
  (fs/spit fs* (state-path root crew) (pr-str state)))
(defn- diary! [fs* root crew at diary]
  (let [dir (str root "/dream/" crew "/diary")]
    (fs/mkdirs fs* dir)
    (fs/spit fs* (str dir "/" (str/replace at ":" "-") ".edn") (pr-str diary))))

(defn- dream-batch! [fs* root cfg crew now provider model soul batch]
  (let [prompt (str "Find lasting habits in these conversations. Respond with JSON propose and reinforce.\n"
                    soul "\nCurrent habits: "
                    (str/join "; " (map (fn [{:keys [id lesson state]}]
                                          (str id " " (name (keyword state)) " " lesson))
                                        (habits/list-habits fs* root crew)))
                    "\n" (str/join "\n" (:lines batch)))
        result (dispatch/dispatch-chat provider {:model model :messages [{:role "user" :content prompt}]})]
    (when (:error result) (throw (ex-info (str (or (:status result) (:message result) (:error result))) {})))
    (let [answer (json/parse-string (:content result) true)
          approval (:approval (settings cfg crew))
          dropped (atom [])
          proposals (reduce (fn [saved {:keys [id lesson supersedes] :as proposal}]
                              (doseq [label (:evidence proposal) :when (not (contains? (:labels batch) label))]
                                (swap! dropped conj {:habit id :label label :reason :not-in-window}))
                              (let [valid (evidence batch (:evidence proposal))]
                                (if (empty? valid)
                                  (do (swap! dropped conj {:habit id :reason :no-evidence}) saved)
                                  (try
                                    (conj saved (habits/propose! fs* root crew lesson valid approval
                                                                 {:id id :dream now :at now :supersedes supersedes}))
                                    (catch Exception _ saved))))) [] (:propose answer))
          reinforced (vec (keep (fn [{:keys [id] :as reinforcement}]
                                  (when-let [valid (seq (evidence batch (:evidence reinforcement)))]
                                    (when (habits/reinforce! fs* root crew id (vec valid) now) id))) (:reinforce answer)))]
      {:proposals proposals :reinforced reinforced :dropped @dropped})))

(defn run! [{:keys [fs root cfg crew session-store now notify! since until]}]
  (let [fs* (or fs (nexus/get :fs) (fs/instance))
        root (or root (nexus/get :root) (loader/root))
        cfg (or cfg (loader/snapshot "dream run"))
        now (or now (str (memory/now)))
        ss (or session-store (nexus/get-in [:sessions :store]) (store/registered-store)
               (sidecar-store/create-store root fs*))
        previous (read-state fs* root crew)
        lock (get-in previous [:lock :at])
        since (or since (:watermark previous))
        until (or until now)
        progress (atom {:at now :window {:since since :until until} :batches 0
                        :sessions [] :proposed [] :reinforced [] :dropped [] :proposals []})]
    (when (and lock (< (- (.toEpochMilli (java.time.Instant/parse now))
                          (.toEpochMilli (java.time.Instant/parse lock))) 3600000))
      (throw (ex-info "already dreaming" {})))
    (when lock (log/warn :dream/stale-lock :crew crew))
    (write-state! fs* root crew (assoc previous :lock {:at now}))
    (try
      (let [sessions (->> (store/list-sessions ss)
                          (filter #(= crew (:crew %)))
                          (map (fn [session] {:id (or (:id session) (:name session))
                                              :entries (store/chronicle-transcript ss (or (:id session) (:name session)))})))
            messages (window sessions since until)]
        (if (empty? (:entries messages))
          {:status :empty :message "no new messages"}
          (let [{:keys [provider model soul]} (resolve/resolve-crew-context cfg crew
                                                                            {:model-override (:model (settings cfg crew))})]
            (doseq [batch (batches messages (:batch (settings cfg crew)))]
              (let [{:keys [proposals reinforced dropped]} (dream-batch! fs* root cfg crew now provider model soul batch)]
                (swap! progress (fn [p] (-> p
                                           (update :batches inc)
                                           (update :sessions into (:sessions batch))
                                           (update :proposed into (map :id proposals))
                                           (update :reinforced into reinforced)
                                           (update :dropped into dropped)
                                           (update :proposals into proposals))))
                (write-state! fs* root crew (assoc previous :lock {:at now}
                                                  :watermark (later (:watermark previous) (:until batch))))))
            (let [diary (-> @progress (dissoc :proposals) (assoc :status "succeeded")
                            (update :sessions #(vec (distinct %))))]
              (diary! fs* root crew now diary)
              (write-state! fs* root crew (assoc previous :lock {:at now}
                                                :watermark (later (:watermark previous) until)))
              (when (seq (:proposals @progress))
                (when notify! (notify! crew (:proposals @progress) nil)))
              diary))))
      (catch Exception e
        (diary! fs* root crew now (-> @progress (dissoc :proposals)
                                     (assoc :status "failed" :error (str (ex-message e)))))
        (when notify! (notify! crew (:proposals @progress) (ex-message e)))
        (throw e))
      (finally (write-state! fs* root crew (dissoc (read-state fs* root crew) :lock))))))

(defn- scheduled-crews [cfg]
  (for [[id _] (:crew cfg)
        :let [crew (name id) dream (settings cfg crew)]
        :when (:enabled dream)]
    [crew dream]))

(defn schedule! [cfg]
  (let [shared (or (nexus/get :scheduler)
                   (throw (ex-info "dream scheduler requires :scheduler" {})))
        zone (or (:tz cfg) (str (java.time.ZoneId/systemDefault)))
        fs* (or (nexus/get :fs) (fs/instance))
        root (or (nexus/get :root) (loader/root))
        ids (mapv (fn [[crew {:keys [schedule]}]]
                    (let [id (keyword "dream" crew)]
                      (scheduler/schedule! shared
                                           {:id id :trigger {:kind :cron :expr schedule :zone zone}
                                            :handler (fn [{:keys [now]}]
                                                       (run! {:cfg cfg :crew crew :now (str now) :root root :fs fs*}))})
                      id))
                  (scheduled-crews cfg))]
    {:scheduler shared :ids ids}))

(defn unschedule! [{:keys [scheduler ids]}]
  (doseq [id ids] (scheduler/cancel! scheduler id)))

(deftype DreamService [crew tasks]
  reconfigurable/Reconfigurable
  (on-load [_ dream]
    (when (:enabled dream)
      (let [cfg (or (loader/snapshot "dream service start") {})]
        (reset! tasks (schedule! (assoc cfg :crew {crew {:dream dream}}))))))
  (on-config-change! [_ _old dream]
    (when-let [old @tasks] (unschedule! old))
    (reset! tasks nil)
    (when (:enabled dream)
      (let [cfg (or (loader/snapshot "dream service reload") {})]
        (reset! tasks (schedule! (assoc cfg :crew {crew {:dream dream}}))))))
  (on-unload [_ _]
    (when-let [old @tasks] (unschedule! old))
    (reset! tasks nil)))

(defn make-service [path _] (->DreamService (name (second path)) (atom nil)))
