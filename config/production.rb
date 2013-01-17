$investigation = { :uri => INVESTIGATION_URI }

$four_store = {
  :uri => 4STORE_URI,
  :user => USER,
  :password => PASS
}

$task = { :uri => TASK_URI }

$user_service = { :uri => USER_SERVICE }
$search_service = { :uri => SEARCH_SERVICE }

# A&A off
$aa ={ :uri => nil }
# example Authorization and Authentcation configuration
# $aa = {
#   :uri => 'https://opensso.in-silico.ch',
#   :free_request => [:HEAD],
#   :authenticate_request => [],
#   :authorize_request => [:GET, :POST, :DELETE, :PUT],
#   :authorize_exceptions => {[:GET,:POST] => [$investigation[:uri], $task[:uri]]}
# }