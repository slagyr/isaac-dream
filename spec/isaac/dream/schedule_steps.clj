(ns isaac.dream.schedule-steps
  (:require
    [gherclj.core :as g :refer [defwhen helper!]]
    [isaac.foundation.config.berths :as berths]
    [isaac.foundation.config.loader :as loader]
    [isaac.foundation.config.config-steps :as config-steps]
    [isaac.foundation.scheduler-steps :as scheduler-steps]
    [isaac.foundation.scheduler.runtime :as scheduler]
    [isaac.foundation.nexus :as nexus]
    [isaac.foundation.spec-helper :as helper]
    [isaac.foundation.fs :as fs]))

(helper! isaac.dream.schedule-steps)

(defn start-service []
  (let [loaded (config-steps/load-result)
        cfg (:config loaded)]
    (g/assoc! :loaded-config-result loaded)
    (g/assoc! :config-berths-installed? true)
    (nexus/register! [:fs] (or (g/get :mem-fs) (fs/real-fs)))
    (nexus/register! [:root] (g/get :root))
    (loader/set-snapshot! cfg "dream feature start")
    (berths/install! {:config cfg :module-index (:module-index cfg)})))

(defwhen "the dream service is started" isaac.dream.schedule-steps/start-service)

(defonce ^:private minute-unit-installed?
  (let [original @#'scheduler-steps/clock-advances]
    (alter-var-root #'scheduler-steps/clock-advances
                    (constantly (fn [duration]
                                  (let [result (original (if (= "\"1m\"" duration) "\"60s\"" duration))]
                                    (helper/await-condition #(not-any? :active-run (scheduler/list-tasks (nexus/get :scheduler))) 3000)
                                    result))))
    true))
