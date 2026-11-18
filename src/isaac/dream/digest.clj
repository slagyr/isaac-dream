(ns isaac.dream.digest
  (:require
    [clojure.string :as str]
    [isaac.agent.comm.delivery.queue :as delivery]
    [isaac.dream.habits :as habits]
    [isaac.foundation.config.loader :as loader]
    [isaac.foundation.fs :as fs]))

(defn settings [cfg crew]
  (let [defaults (get-in cfg [:defaults :crew :dream])
        specific (:dream (or (get-in cfg [:crew crew]) (get-in cfg [:crew (keyword crew)])))]
    (merge {:enabled false :approval :manual :batch 400 :batch-chars 200000} defaults specific)))

(defn send! [cfg fs* root-dir crew proposals error & [contradicted retired retire-proposed]]
  (let [cfg (or cfg (loader/load-config! (loader/root) (fs/instance) "dream digest"))
        {:keys [comm to]} (or (:digest (settings cfg crew))
                              (let [{:keys [comm target]} (get-in cfg [:attention :notify])]
                                {:comm comm :to target}))]
    (when (and comm to)
      (delivery/enqueue! {:comm (keyword comm) :target to
                          :content (if error
                                     (str crew " dream failed: " error)
                                     (str crew " dreamed: "
                                          (str/join "; " (concat (map (fn [{:keys [id lesson]}]
                                                                 (str id ": " lesson " — dream approve " id " --crew " crew)) proposals)
                                                         (map (fn [id] (str id ": " (:lesson (habits/find-habit fs* root-dir crew id))
                                                                            " contradicted — dream retire " id " --crew " crew))
                                                              (remove (set retired) contradicted))
                                                         (map (fn [id] (str id ": retired — dream approve " id " --crew " crew)) retired)
                                                         (map (fn [id] (str id ": faded — dream retire " id " --crew " crew)) retire-proposed)))))
                          :origin {:kind :dream} :crew crew}))))
