TARGET_APP_FILTER = ""
MOCK_RULES = {}
def get_mock_response(url):
    for pattern, response in MOCK_RULES.items():
        if pattern in url:
            return response
    return None
def add_mock_rule(url_pattern, body, content_type="text/plain; charset=UTF-8"):
    MOCK_RULES[url_pattern] = {"body": body, "content_type": content_type}
