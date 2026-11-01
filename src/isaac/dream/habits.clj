(ns isaac.dream.habits
  (:require
    [clojure.edn :as edn]
    [clojure.string :as str]
    [isaac.foundation.fs :as fs]))

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
    (when (= "active" (name (:state habit)))
      (save! fs* root crew (update habit :history (fnil conj []) (event at :reinforced {:dream at} evidence))))))

(defn wipe! [fs* root crew]
  (doseq [{:keys [id]} (list-habits fs* root crew)]
    (fs/delete fs* (habit-path root crew id))))

(defn section [{:keys [fs root crew]}]
  (let [lessons (->> (list-habits fs root crew)
                     (filter #(= "active" (name (:state %))))
                     (map :lesson))]
    (when (seq lessons)
      {:text (str/join "\n" (cons "These are lessons this crew learned" lessons))})))
