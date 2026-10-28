(ns isaac.dream.module-spec
  (:require
    [speclj.core :refer :all]
    [isaac.foundation.module.protocol :as module]
    [isaac.dream.module :as dream-module]))

(describe "isaac.dream.module"
  (it "create-module returns a valid Module instance"
    (should (module/module? (dream-module/create-module)))))
