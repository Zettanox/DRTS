import re

with open("/home/overlord/AG/Stoa-devel/src-tauri/src/network/mod.rs", "r") as f:
    content = f.read()

replacement = """                            let pid_str = connected_peer.to_string();
                            let is_relay = match &endpoint {
                                libp2p::core::ConnectedPoint::Dialer { address, .. } => {
                                    address.to_string().contains("p2p-circuit")
                                }
                                libp2p::core::ConnectedPoint::Listener { local_addr, send_back_addr } => {
                                    local_addr.to_string().contains("p2p-circuit") || send_back_addr.to_string().contains("p2p-circuit")
                                }
                            };
                            let conn_type = if is_relay { PeerConnectionType::Relay } else { PeerConnectionType::Lan };"""

pattern = r"""                            let pid_str = connected_peer.to_string\(\);\n                            let is_lan = peers_clone\.lock\(\)\.await\.contains_key\(&pid_str\);\n                            let conn_type = if is_lan { PeerConnectionType::Lan } else { PeerConnectionType::Relay };"""

new_content = re.sub(pattern, replacement, content)

if new_content != content:
    with open("/home/overlord/AG/Stoa-devel/src-tauri/src/network/mod.rs", "w") as f:
        f.write(new_content)
    print("Replaced!")
else:
    print("No change!")
