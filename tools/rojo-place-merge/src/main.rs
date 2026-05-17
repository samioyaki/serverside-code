use std::{
    env,
    error::Error,
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    path::Path,
};

use rbx_dom_weak::{types::Ref, WeakDom};

const PRESERVED_PATHS: &[&[&str]] = &[
    &["ReplicatedStorage", "Remotes"],
    &["ReplicatedStorage", "Assets"],
    &["ReplicatedStorage", "Assets", "Baddies"],
    &["Workspace", "Game"],
];

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!(
            "Usage: rojo-place-merge <base-place.rbxl> <rojo-built-place.rbxl> <output.rbxl>"
        );
        std::process::exit(2);
    }

    let base_path = Path::new(&args[1]);
    let source_path = Path::new(&args[2]);
    let output_path = Path::new(&args[3]);

    let mut base_dom = read_place(base_path)?;
    let source_dom = read_place(source_path)?;

    sync_direct_children(
        &source_dom,
        &mut base_dom,
        &["ReplicatedStorage"],
        &["Assets", "Remotes"],
    )?;
    sync_direct_children(&source_dom, &mut base_dom, &["ServerScriptService"], &[])?;
    sync_direct_children(
        &source_dom,
        &mut base_dom,
        &["StarterPlayer", "StarterPlayerScripts"],
        &[],
    )?;

    for path in PRESERVED_PATHS {
        ensure_path_from_source(&source_dom, &mut base_dom, path)?;
    }

    let temp_output_path = output_path.with_extension("rbxl.tmp");
    write_place(&temp_output_path, &base_dom)?;
    fs::rename(&temp_output_path, output_path)?;

    println!(
        "Merged {} Rojo scripts into {}",
        count_scripts(&source_dom),
        output_path.display()
    );

    Ok(())
}

fn read_place(path: &Path) -> Result<WeakDom, Box<dyn Error>> {
    let file = File::open(path)?;
    Ok(rbx_binary::from_reader(BufReader::new(file))?)
}

fn write_place(path: &Path, dom: &WeakDom) -> Result<(), Box<dyn Error>> {
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);
    let top_level_refs = dom.root().children().to_vec();
    rbx_binary::to_writer(&mut writer, dom, &top_level_refs)?;
    writer.flush()?;
    Ok(())
}

fn sync_direct_children(
    source: &WeakDom,
    dest: &mut WeakDom,
    parent_path: &[&str],
    preserve_names: &[&str],
) -> Result<(), Box<dyn Error>> {
    let source_parent = find_path(source, parent_path)
        .ok_or_else(|| format!("source path not found: {}", parent_path.join("/")))?;
    let dest_parent = ensure_path_from_source(source, dest, parent_path)?;
    let children = source
        .get_by_ref(source_parent)
        .expect("source parent ref should exist")
        .children()
        .to_vec();

    for source_child_ref in children {
        let source_child = source
            .get_by_ref(source_child_ref)
            .expect("source child ref should exist");
        let name = source_child.name.as_str();

        if preserve_names.contains(&name) {
            continue;
        }

        destroy_all_named_children(dest, dest_parent, name);
        clone_under(source, source_child_ref, dest, dest_parent);
    }

    Ok(())
}

fn ensure_path_from_source(
    source: &WeakDom,
    dest: &mut WeakDom,
    path: &[&str],
) -> Result<Ref, Box<dyn Error>> {
    if path.is_empty() {
        return Ok(dest.root_ref());
    }

    if let Some(existing) = find_path(dest, path) {
        return Ok(existing);
    }

    let parent_ref = ensure_path_from_source(source, dest, &path[..path.len() - 1])?;
    let source_ref = find_path(source, path)
        .ok_or_else(|| format!("source path not found: {}", path.join("/")))?;

    Ok(clone_under(source, source_ref, dest, parent_ref))
}

fn clone_under(source: &WeakDom, source_ref: Ref, dest: &mut WeakDom, dest_parent: Ref) -> Ref {
    let cloned_ref = source.clone_into_external(source_ref, dest);
    dest.transfer_within(cloned_ref, dest_parent);
    cloned_ref
}

fn destroy_all_named_children(dom: &mut WeakDom, parent: Ref, name: &str) {
    while let Some(existing) = find_child(dom, parent, name) {
        dom.destroy(existing);
    }
}

fn find_path(dom: &WeakDom, path: &[&str]) -> Option<Ref> {
    let mut current = dom.root_ref();

    for segment in path {
        current = find_child(dom, current, segment)?;
    }

    Some(current)
}

fn find_child(dom: &WeakDom, parent: Ref, name: &str) -> Option<Ref> {
    let parent_instance = dom.get_by_ref(parent)?;

    for child_ref in parent_instance.children() {
        let child = dom.get_by_ref(*child_ref)?;
        if child.name == name {
            return Some(*child_ref);
        }
    }

    None
}

fn count_scripts(dom: &WeakDom) -> usize {
    dom.descendants()
        .filter(|instance| {
            matches!(
                instance.class.as_str(),
                "Script" | "LocalScript" | "ModuleScript"
            )
        })
        .count()
}
