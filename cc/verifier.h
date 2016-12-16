// Verifies CC result by performing a BFS from a vertex in each component
// - Asserts search does not reach a vertex with a different component label
// - If the graph is directed, it performs the search as if it was undirected
// - Asserts every vertex is visited (degree-0 vertex should have own label)
bool CCVerifier(int m, int *row_offsets, int *column_indices, CompT *comp) {
	printf("Verifying...\n");
	unordered_map<NodeID, NodeID> label_to_source;
	vector<bool> visited(m);
	vector<NodeID> frontier;
	for (NodeID i=0; i<m; i++) {
		visited[i] = false;
		label_to_source[comp[i]] = i;
	}
	frontier.reserve(m);
	for (auto label_source_pair : label_to_source) {
		NodeID curr_label = label_source_pair.first;
		NodeID source = label_source_pair.second;
		frontier.clear();
		frontier.push_back(source);
		visited[source] = true;
		for (auto it = frontier.begin(); it != frontier.end(); it++) {
			NodeID src = *it;
			unsigned row_begin = row_offsets[src];
			unsigned row_end = row_offsets[src + 1]; 
			for (unsigned offset = row_begin; offset < row_end; ++ offset) {
				int dst = column_indices[offset];
				if (comp[dst] != curr_label)
					return false;
				if (!visited[dst]) {
					visited[dst] = true;
					frontier.push_back(dst);
				}
			}
			/*
			if (is_directed()) {
				for (unsigned offset = row_begin; offset < row_end; ++ offset) {
					int dst = column_indices[offset];
					if (comp[dst] != curr_label)
						return false;
					if (!visited[dst]) {
						visited[dst] = true;
						frontier.push_back(dst);
					}
				}
			}
			*/
		}   
	}
	for (NodeID n = 0; n < m; n ++)
		if (!visited[n])
			return false;
	return true;
}
