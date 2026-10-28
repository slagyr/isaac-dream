(ns isaac.dream.habit-steps
  (:require
    [gherclj.core :as g :refer [defthen helper!]]
    [isaac.dream.habits :as habits]
    [isaac.foundation.fs :as fs]
    [isaac.foundation.nexus :as nexus]
    [isaac.foundation.step-tables :as match]))

(helper! isaac.dream.habit-steps)

(defn crew-has-habit [crew table]
  (let [fs*     (or (g/get :mem-fs) (nexus/get :fs) (fs/real-fs))
        results (map #(match/match-object table %)
                     (habits/list-habits fs* (g/get :root) crew))]
    (g/should (some :pass? results))))

(defthen "crew {id:string} has a habit matching:" isaac.dream.habit-steps/crew-has-habit)
