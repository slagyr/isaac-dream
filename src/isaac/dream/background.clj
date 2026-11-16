(ns isaac.dream.background
  (:require
    [clojure.string :as str]
    [isaac.agent.session.store.spi :as store]
    [isaac.dream.habits :as habits]))

(defn- quoted-evidence [ss crew evidence]
  (for [{:keys [session entries]} evidence
        id entries
        :let [record (when ss (store/get-session ss session))
              transcript (when (= crew (:crew record)) (store/chronicle-transcript ss session))
              entry (first (filter #(= id (:id %)) transcript))]]
    (if entry
      (str session " " (str/replace (:timestamp entry) #"(?<!Z)$" "Z") " "
           (get-in entry [:message :role]) ": "
           (let [content (get-in entry [:message :content])]
             (if (string? content) content (str/join "" (map :text content)))))
      (str session " missing evidence " id))))

(defn render [habit crew ss strength-config]
  (let [days (habits/active-days ss crew)]
    (str/join "\n"
              (concat [(str "Rule: " (:lesson habit))
                       (str "Why: " (or (:why habit) ""))
                       (str "Strength: " (format "%.1f" (habits/strength habit days strength-config)))
                       (str "Pinned: " (if (:pinned habit) "yes" "no"))]
                      (quoted-evidence ss crew (:evidence habit))
                      (mapcat (fn [{:keys [at event kind evidence]}]
                                (cons (str at " " (name event) (when kind (str " " (name kind))))
                                      (quoted-evidence ss crew evidence)))
                              (:history habit))))))
