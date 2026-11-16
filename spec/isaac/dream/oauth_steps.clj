(ns isaac.dream.oauth-steps
  (:require
    [gherclj.core :as g :refer [defgiven defthen helper!]]
    [isaac.agent.llm.auth.store :as auth-store]
    [isaac.agent.llm.api.grover :as grover]
    [isaac.agent.llm.http :as llm-http]
    [isaac.foundation.cli-steps :as fcli]
    [isaac.foundation.nexus :as nexus]))

;; Exercise the real OAuth providers without allowing outbound network traffic.
(fcli/register-isaac-run-wrapper!
  (fn [thunk]
    (with-redefs [llm-http/post-json! (fn [url headers body & _]
                                        (grover/post-json! "grok" url headers body))
                  llm-http/post-sse! (fn [url headers body on-chunk process-event initial & _]
                                       (grover/post-sse! "chatgpt" url headers body
                                                         on-chunk process-event initial))]
      (thunk))))

(helper! isaac.dream.oauth-steps)

(defn stored-oauth-login [provider token]
  (let [fs* (g/get :mem-fs)]
    (nexus/-with-nested-nexus {:fs fs*}
      (auth-store/save-tokens! (g/get :root) provider
                               {:access_token token :refresh_token "rt-moonflowers" :expires_in 3600}
                               fs*))))

(defn dream-request-carries-token [token]
  (let [requests (grover/provider-requests)]
    (g/should (some #(= (str "Bearer " token) (get-in % [:headers "Authorization"])) requests))))

(defgiven "a stored OAuth login for {provider:string} with access token {token:string}"
  isaac.dream.oauth-steps/stored-oauth-login)
(defthen "the dream provider request carries access token {token:string}"
  isaac.dream.oauth-steps/dream-request-carries-token)
