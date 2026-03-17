use std::collections::HashMap;
use std::fmt;

const MAX_ITEMS: usize = 1000;

static APP_NAME: &str = "fluoride-example";

pub enum Status {
    Active,
    Inactive,
    Archived,
}

pub struct Item {
    id: u64,
    name: String,
    tags: Vec<String>,
}

pub trait Searchable {
    fn matches(&self, query: &str) -> bool;
    fn relevance(&self, query: &str) -> f64;
}

impl Searchable for Item {
    fn matches(&self, query: &str) -> bool {
        self.name.contains(query) || self.tags.iter().any(|t| t.contains(query))
    }

    fn relevance(&self, query: &str) -> f64 {
        if self.name == query {
            1.0
        } else if self.name.contains(query) {
            0.5
        } else {
            0.1
        }
    }
}

impl fmt::Display for Item {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}({})", self.name, self.id)
    }
}

pub struct Inventory {
    items: HashMap<u64, Item>,
    next_id: u64,
}

impl Inventory {
    pub fn new() -> Self {
        Self {
            items: HashMap::new(),
            next_id: 1,
        }
    }

    pub fn add(&mut self, name: &str, tags: Vec<String>) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        self.items.insert(
            id,
            Item {
                id,
                name: name.to_string(),
                tags,
            },
        );
        id
    }

    pub fn search(&self, query: &str) -> Vec<&Item> {
        let mut results: Vec<&Item> = self
            .items
            .values()
            .filter(|item| item.matches(query))
            .collect();
        results.sort_by(|a, b| b.relevance(query).partial_cmp(&a.relevance(query)).unwrap());
        results
    }
}

type ItemId = u64;

pub fn format_items(items: &[&Item]) -> String {
    items
        .iter()
        .map(|item| item.to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

macro_rules! log {
    ($level:expr, $($arg:tt)*) => {
        println!("[{}] {}", $level, format!($($arg)*));
    };
}

fn main() {
    let mut inventory = Inventory::new();
    inventory.add("Widget", vec!["hardware".into(), "small".into()]);
    inventory.add("Gadget", vec!["electronics".into()]);

    let results = inventory.search("Widget");
    log!("INFO", "Found: {}", format_items(&results));
}
