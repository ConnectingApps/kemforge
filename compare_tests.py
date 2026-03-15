
import re

def parse_ps1(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Matches: Write-TestHeader "1. Simple GET Request"
    # Handling potential multiline strings in PS1
    matches = re.findall(r'Write-TestHeader\s+"([^"]+)"', content)
    return matches

def parse_md(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Matches: ## 1. Simple GET Request or ### 1. Simple GET Request
    matches = re.findall(r'^#{2,3}\s+(.*)', content, re.MULTILINE)
    return matches

ps1_tests = parse_ps1('/home/daan-acohen/repos/KemForge/test_curl.ps1')
md_tests = parse_md('/home/daan-acohen/repos/KemForge/CURL_FEATURES.md')

print(f"PS1 tests: {len(ps1_tests)}")
print(f"MD tests: {len(md_tests)}")

# Normalize titles: remove leading numbers and trailing dots/whitespace
def normalize(title):
    # Remove things like "1. ", "55.1. ", "102b. ", etc.
    res = re.sub(r'^\d+(\.\d+)*[ab]?\.\s*', '', title)
    # Remove backticks
    res = res.replace('`', '')
    # Remove things in parentheses
    res = re.sub(r'\s*\(.*\)\s*', ' ', res)
    # Remove common extra words or chars
    res = res.replace('/', ' ')
    res = res.replace('--', ' ')
    return " ".join(res.strip().lower().split())

def get_number(title):
    m = re.match(r'^(\d+(\.\d+)*[ab]?)', title)
    return m.group(1) if m else title

ps1_nums = [get_number(t) for t in ps1_tests]
md_nums = [get_number(t) for t in md_tests]

print(f"\nUnique PS1 numbers: {len(set(ps1_nums))}")
print(f"Unique MD numbers: {len(set(md_nums))}")

ps1_set = set(ps1_nums)
md_set = set(md_nums)

print("\nNumbers in PS1 not in MD:")
for n in sorted(ps1_set, key=lambda x: [int(v) if v.isdigit() else v for v in re.split(r'(\d+)', x) if v]):
    if n not in md_set:
        print(f"  {n}")

print("\nNumbers in MD not in PS1:")
for n in sorted(md_set, key=lambda x: [int(v) if v.isdigit() else v for v in re.split(r'(\d+)', x) if v]):
    if n not in ps1_set:
        print(f"  {n}")
