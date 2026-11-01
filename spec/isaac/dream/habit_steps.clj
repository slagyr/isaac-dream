(ns isaac.dream.habit-steps
  (:require
    [gherclj.core :as g :refer [defthen helper!]]
    [clojure.string :as str]
    [isaac.agent.session.session-steps :as session-steps]
    [isaac.dream.habits :as habits]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.nexus :as nexus]
    [isaac.foundation.step-tables :as match]
    [isaac.foundation.spec-helper :as helper]))

(helper! isaac.dream.habit-steps)

(defn- resolve-negative-indices [habit path]
  (str/replace path #"([\w-]+)\[-(\d+)\]"
               (fn [[_ field offset]]
                 (let [entries (get habit (keyword field))
                       index (- (count entries) (parse-long offset))]
                   (str field "[" index "]")))))

(defn- matching-habit? [fs* root crew table]
  (some (fn [habit]
          (:pass? (match/match-object
                    (update table :rows
                            #(mapv (fn [[path value]] [(resolve-negative-indices habit path) value]) %))
                    habit)))
        (habits/list-habits fs* root crew)))

(defn crew-has-habit [crew table]
  (session-steps/await-turn!)
  (let [fs* (or (g/get :mem-fs) (nexus/get :fs) (fs/real-fs))
        root (g/get :root)]
    (helper/await-condition #(matching-habit? fs* root crew table) 3000)
    (g/should (matching-habit? fs* root crew table))))

(defthen "crew {id:string} has a habit matching:" isaac.dream.habit-steps/crew-has-habit)
