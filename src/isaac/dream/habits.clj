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
         (mapv (fn [filename]
                 (let [id (subs filename 0 (- (count filename) 4))]
                   (assoc (edn/read-string (fs/slurp fs* (habit-path root crew id)))
                          :id id)))))))

(defn propose! [fs* root crew lesson evidence approval]
  (when-not (and (string? lesson) (not (str/blank? lesson)))
    (throw (ex-info "lesson is required" {})))
  (when-not (and (vector? evidence) (seq evidence) (every? #(and (string? %) (not (str/blank? %))) evidence))
    (throw (ex-info "evidence must contain session names" {})))
  (let [id    (str (java.util.UUID/randomUUID))
        habit {:state (if (= :auto approval) :active :proposed)
               :lesson lesson :evidence evidence}]
    (fs/mkdirs fs* (crew-dir root crew))
    (fs/spit fs* (habit-path root crew id) (pr-str habit))
    (assoc habit :id id)))

(defn change-state! [fs* root crew id state]
  (let [path (habit-path root crew id)]
    (when-not (fs/file? fs* path)
      (throw (ex-info "Habit not found" {:id id})))
    (let [habit (assoc (edn/read-string (fs/slurp fs* path)) :state state)]
      (fs/spit fs* path (pr-str habit))
      (assoc habit :id id))))

(defn wipe! [fs* root crew]
  (doseq [{:keys [id]} (list-habits fs* root crew)]
    (fs/delete fs* (habit-path root crew id))))

(defn section [{:keys [fs root crew]}]
  (let [lessons (->> (list-habits fs root crew)
                     (filter #(= "active" (name (:state %))))
                     (map :lesson))]
    (when (seq lessons)
      {:text (str/join "\n" (cons "These are lessons this crew learned" lessons))})))
