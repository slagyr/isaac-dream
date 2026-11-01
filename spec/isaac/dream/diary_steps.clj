(ns isaac.dream.diary-steps
  (:require
    [clojure.edn :as edn]
    [clojure.string :as str]
    [gherclj.core :as g :refer [helper!]]
    [isaac.agent.comm.comm-steps]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.step-tables :as match]))

(helper! isaac.dream.diary-steps)

(defn- diary-path? [path]
  (boolean (re-matches #"dream/[^/]+/diary" path)))

(defn- newest-diary [path]
  (let [fs* (g/get :mem-fs)
        dir (str (g/get :root) "/" path)
        latest (last (sort (fs/children fs* dir)))]
    (g/should (some? latest))
    (edn/read-string (fs/slurp fs* (str dir "/" latest)))))

(defn- get-path [data path]
  (reduce (fn [value [_ field index]]
            (let [value (get value (keyword field))]
              (if index (nth value (parse-long index) nil) value)))
          data
          (re-seq #"([\w-]+)(?:\[(\d+)\])?" path)))

(defn- matches? [expected actual]
  (if (str/starts-with? expected "#\"")
    (boolean (and (string? actual)
                  (re-matches (re-pattern (subs expected 2 (dec (count expected)))) actual)))
    (= expected (if (keyword? actual) (name actual) (str actual)))))

;; The shared delivery-queue step expects map-only paths and EDN literals.
;; Diary evidence indexes and regex cells use the same real file, with
;; the feature table dialect understood by this adapter.
(let [original @#'isaac.agent.comm.comm-steps/newest-file-in-edn-contains]
  (alter-var-root #'isaac.agent.comm.comm-steps/newest-file-in-edn-contains
                  (constantly (fn [path table]
                                (if (and (diary-path? path)
                                         (some (fn [[p v]] (or (str/includes? p "[")
                                                               (str/starts-with? v "#\""))) (:rows table)))
                                  (let [diary (newest-diary path)]
                                    (doseq [[path expected] (:rows table)]
                                      (g/should (matches? expected (get-path diary path)))))
                                  (original path table))))))
