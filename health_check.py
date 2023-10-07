from flask import Flask, request, jsonify, json
import requests


app = Flask(__name__)
app.json.sort_keys = False

# Replace with the third-party API URL for sei block info
THIRD_PARTY_API_URL = (
    "https://rpc.cros-nest.com/sei/"
)

# Replace with your sei node RPC URL
SEINODE_RPC_URL = "http://20.9.57.26:26657/"
@app.route("/test", methods=["GET"])
def get_test():
    try:
        url = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
        headers = {"Metadata": "true"}
        response = requests.get(url, headers=headers)
        print("blockchain_info:", response.text)
        return (
                jsonify(
                    {
                        "status": "success",
                        "message": "sei node is healthy",
                        "blockchain_info":response.text
                    }),
                200,
            )
    except Exception as e:
       print("Error:", e)
       return jsonify({"status": "error"}), 500
    

@app.route("/health", methods=["GET"])
def get_sei_node_health():
    try:
        # Get the number of connected peers
        peer_count_response = requests.get(SEINODE_RPC_URL+"net_info")
        peer_count = peer_count_response.json().get("n_peers")
        
        if peer_count == 0:
            print("No peers connected")
            return jsonify({"status": "error", "message": "No peers connected"}), 500
        
        # Get the last block number from your sei node
        node_response = requests.get(SEINODE_RPC_URL+"abci_info")
        blockchain_info = node_response.json().get("response")
        last_block_number = blockchain_info.get("last_block_height")

        # Get the last block number from the third-party API
        third_party_response = requests.get(THIRD_PARTY_API_URL+"abci_info")
        third_party_last_block_number = (
            third_party_response.json().get("response").get("last_block_height")
        )

        # Check if sei node is behind more than 50 blocks 
        print("third_party_last_block_number", int(third_party_last_block_number) - int(last_block_number))
        # Check if Zcash node is behind more than 100 blocks 
        if int(third_party_last_block_number) - int(last_block_number) > 100:
            print(
                "Last block number mismatch between your sei node and the third-party API"
            )
            return (
                jsonify(
                    {
                        "status": "error",
                        "message": "Last block number mismatch between your sei node and the third-party API",
                    }
                ),
                500,
            )
        return (
                jsonify(
                    {
                        "status": "success",
                        "message": "sei node is healthy",
                        "peer_count": peer_count,
                        "last_block_number": last_block_number,
                        "third_party_last_block_number": third_party_last_block_number
                    }),
                500,
            )
    except Exception as e:
       print("Error:", e)
       return jsonify({"status": "error"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9000)
