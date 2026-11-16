(ns isaac.dream.habits
  (:require
    [clojure.edn :as edn]
    [clojure.string :as str]
    [isaac.foundation.fs :as fs]
    [isaac.agent.session.store.spi :as store]
    [isaac.agent.session.store.sidecar :as sidecar-store]))

(defn- valid-id? [id]
  (boolean (and (string? id) (re-matches #"[a-zA-Z0-9_-]+" id))))

(defn- crew-dir [root crew]
  (when-not (valid-id? crew)
    (throw (ex-info "Invalid crew id" {:crew crew})))
  (str root "/dream/" crew))

(defn- habit-path [root crew id]
  (when-not (valid-id? id)
    (throw (ex-info "Invalid habit id" {:id id})))
  (str (crew-dir root crew) "/" id ".edn"))

(defn list-habits [fs* root crew]
  (let [dir (crew-dir root crew)]
    (->> (fs/children fs* dir)
         (filter #(re-matches #"[a-zA-Z0-9_-]+\.edn" %))
         (remove #{"state.edn"})
         (mapv (fn [filename]
                 (let [id (subs filename 0 (- (count filename) 4))]
                   (assoc (edn/read-string (fs/slurp fs* (habit-path root crew id)))
                          :id id)))))))

(defn save! [fs* root crew habit]
  (fs/mkdirs fs* (crew-dir root crew))
  (fs/spit fs* (habit-path root crew (:id habit)) (pr-str (dissoc habit :id)))
  habit)

(defn find-habit [fs* root crew id]
  (first (filter #(= id (:id %)) (list-habits fs* root crew))))

(defn event [at type source & [evidence]]
  (cond-> {:at at :event type :by source}
    evidence (assoc :evidence evidence)))

(defn propose!
  ([fs* root crew lesson evidence approval]
   (propose! fs* root crew lesson evidence approval {}))
  ([fs* root crew lesson evidence approval {:keys [id dream supersedes at]}]
   (when-not (and (string? lesson) (not (str/blank? lesson)))
     (throw (ex-info "lesson is required" {})))
   (when-not (and (vector? evidence) (seq evidence)
                  (every? #(or (and (string? %) (not (str/blank? %)))
                               (and (string? (:session %)) (seq (:entries %)))) evidence))
     (throw (ex-info "evidence must contain sessions and entries" {})))
   (let [id (or id (str (java.util.UUID/randomUUID)))
         at (or at (str (java.time.Instant/now)))
         habit (cond-> {:id id :state (if (= :auto approval) :active :proposed)
                        :lesson lesson :evidence evidence
                        :history (cond-> [(event at :proposed (if dream {:dream dream} :crew))]
                                   (= :auto approval) (conj (event at :approved :auto)))}
                 dream (assoc :dream dream)
                 (seq supersedes) (assoc :supersedes (vec supersedes)))]
     (when (find-habit fs* root crew id)
       (throw (ex-info "Habit already exists" {:id id})))
     (save! fs* root crew habit)
     (when (= :auto approval)
       (doseq [old supersedes]
         (when-let [prior (find-habit fs* root crew old)]
           (save! fs* root crew (-> prior (assoc :state :retired :superseded-by id)
                                     (update :history (fnil conj []) (event at :superseded :auto)))))))
     habit)))

(defn change-state! [fs* root crew id state]
  (let [habit (find-habit fs* root crew id)]
    (when-not habit (throw (ex-info "Habit not found" {:id id})))
    (let [at (str (java.time.Instant/now))
          updated (-> habit (assoc :state state)
                      (update :history (fnil conj [])
                              (event at ({:active :approved :rejected :rejected :retired :retired} state) :operator)))]
      (save! fs* root crew updated)
      (when (= state :active)
        (doseq [old (:supersedes habit)]
          (when-let [prior (find-habit fs* root crew old)]
            (save! fs* root crew (-> prior (assoc :state :retired :superseded-by id)
                                      (update :history (fnil conj []) (event at :superseded :operator)))))))
      updated)))

(defn reinforce! [fs* root crew id evidence at]
  (when-let [habit (find-habit fs* root crew id)]
    (when (#{"active" "proposed"} (name (:state habit)))
      (save! fs* root crew (update habit :history (fnil conj []) (event at :reinforced {:dream at} evidence))))))

(defn pin! [fs* root crew id pinned?]
  (let [habit (or (find-habit fs* root crew id)
                  (throw (ex-info "Habit not found" {:id id})))
        at (str (java.time.Instant/now))]
    (save! fs* root crew (-> habit
                            (assoc :pinned pinned?)
                            (update :history (fnil conj [])
                                    (event at (if pinned? :pinned :unpinned) :operator))))))

(defn- utc-day [timestamp]
  (when timestamp
    (try (str (.toLocalDate (.atZone (java.time.Instant/parse (str/replace timestamp #"(?<!Z)$" "Z")) java.time.ZoneOffset/UTC)))
         (catch Exception _ nil))))

(defn active-days [session-store crew]
  (if session-store
    (->> (store/list-sessions session-store)
         (filter #(= (name crew) (some-> (:crew %) name)))
         (mapcat #(store/chronicle-transcript session-store (or (:id %) (:name %))))
         (keep (comp utc-day :timestamp))
         set)
    #{}))

(defn- event-kind [{:keys [event kind]}]
  (if (= event :reinforced) [event (or kind :taught)] [event]))

(defn strength [habit days {:keys [half-life-days approved reinforced contradicted]
                            :or {half-life-days 30 approved 2 reinforced 1 contradicted -4}}]
  (let [weights {:approved approved :reinforced reinforced :contradicted contradicted}]
    (->> (:history habit)
         (filter #(contains? weights (:event %)))
         (group-by (juxt (comp utc-day :at) event-kind))
         (map (fn [[[day [type]] _]]
                (let [elapsed (count (filter #(pos? (compare % day)) days))]
                  (* (get weights type) (Math/pow 0.5 (/ elapsed (double half-life-days)))))))
         (reduce + 0.0))))

(defn- dream-settings [config crew]
  (merge {:prompt-chars 6000 :strength {:half-life-days 30}}
         (get-in config [:defaults :crew :dream])
         (get-in config [:crew (name crew) :dream])
         (get-in config [:crew (keyword crew) :dream])))

(defn wipe! [fs* root crew]
  (doseq [{:keys [id]} (list-habits fs* root crew)]
    (fs/delete fs* (habit-path root crew id))))

(defn section [{:keys [fs root crew config session-store]}]
  (let [{:keys [prompt-chars] :as settings} (dream-settings config crew)
        ss (or session-store (store/registered-store) (sidecar-store/create-store root fs))
        days (active-days ss crew)
        habits (->> (list-habits fs root crew)
                    (filter #(= :active (keyword (:state %))))
                    (sort-by (fn [habit] [(if (:pinned habit) 0 1)
                                          (- (strength habit days (:strength settings))) (:id habit)])))
        lessons (loop [[habit & rest] habits used 0 selected []]
                  (if-not habit
                    selected
                    (let [lesson (:lesson habit)
                          next-used (+ used (count lesson))]
                      (if (or (:pinned habit) (<= next-used prompt-chars))
                        (recur rest next-used (conj selected lesson))
                        selected))))]
    (when (seq lessons)
      {:text (str/join "\n" (cons "These are lessons this crew learned" lessons))})))
